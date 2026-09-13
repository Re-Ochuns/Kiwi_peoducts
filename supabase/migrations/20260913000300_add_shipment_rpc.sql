begin;

alter table public.shipments add column correlation_id uuid, add column reason text;
alter table public.inventory_events add column correlation_id uuid;

-- Planned allocations remain immutable; subtract active shipment facts to
-- derive the allocation of the remaining physical inventory.
create function private.shipped_weight(order_value uuid, lot_value uuid default null)
returns numeric language sql stable set search_path = '' as $$
 select coalesce(sum(l.shipped_weight_kg),0) from public.shipment_lines l
 join public.shipments s on s.id=l.shipment_id join public.containers c on c.id=l.container_id
 where s.status='confirmed' and s.order_id=order_value
 and (lot_value is null or c.ripening_lot_id=lot_value);
$$;
create function private.remaining_lot_use(lot_value uuid)
returns text language sql stable set search_path = '' as $$
 with weights as (
 select coalesce((select sum(greatest(0,a.allocated_weight_kg-private.shipped_weight(a.order_id,lot_value)))
 from public.ripening_allocations a join public.orders o on o.id=a.order_id
 where a.ripening_lot_id=lot_value and o.status not in ('cancelled','shipped')),0) as allocated,
 coalesce((select sum(current_weight_kg) from public.containers where ripening_lot_id=lot_value),0) as remaining)
 select case when allocated=0 then 'reserve' when remaining>allocated then 'mixed' else 'order' end from weights;
$$;

create function public.shipment_get(shipment_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
 select to_jsonb(s)||jsonb_build_object('lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.container_id)
 from public.shipment_lines l where l.shipment_id=s.id),'[]'::jsonb),
 'total_weight_kg',(select sum(shipped_weight_kg) from public.shipment_lines where shipment_id=s.id))
 from public.shipments s where s.id=shipment_id_value;
$$;
create function public.shipment_list(order_id_value uuid default null)
returns setof public.shipments language sql stable security invoker set search_path = '' as $$
 select * from public.shipments where order_id_value is null or order_id=order_id_value order by shipped_at desc,id;
$$;
create function public.shipment_container_list(order_id_value uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
 'remaining_use_type',private.remaining_lot_use(c.ripening_lot_id),
 'available_weight_kg',greatest(0,least(c.current_weight_kg-c.reserved_weight_kg,
 a.allocated_weight_kg-private.shipped_weight(o.id,c.ripening_lot_id),
 o.ordered_weight_kg-private.shipped_weight(o.id)))) order by c.display_id,c.id),'[]'::jsonb)
 from public.containers c join public.ripening_allocations a on a.ripening_lot_id=c.ripening_lot_id
 join public.orders o on o.id=a.order_id
 where private.current_user_is_active() and o.id=order_id_value
 and o.status in ('confirmed','in_progress','partially_shipped')
 and c.status='shippable' and c.current_weight_kg>c.reserved_weight_kg
 and least(c.shippable_until,c.best_before_at)>statement_timestamp()
 and c.shippable_until is not null and c.best_before_at is not null;
$$;

create function public.shipment_inventory_list()
returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('remaining_use_type',private.remaining_lot_use(c.ripening_lot_id)) order by c.display_id,c.id),'[]'::jsonb)
 from public.containers c where private.current_user_is_active() and c.ripening_lot_id is not null;
$$;

create function private.refresh_shipped_order(order_value uuid,actor uuid,correlation uuid,reason_value text,worker_value uuid)
returns void language plpgsql set search_path = '' as $$
declare old_order public.orders%rowtype; new_order public.orders%rowtype; shipped numeric;
 t public.work_tasks%rowtype; new_status text;
begin
 select * into strict old_order from public.orders where id=order_value for update;
 shipped:=private.shipped_weight(order_value);
 if old_order.status='cancelled' then
   perform private.rpc_fail('KW409','ORDER_UNAVAILABLE','キャンセル済み受注の出荷は変更できません。',null);
 end if;
 update public.orders set status=case when shipped>=ordered_weight_kg then 'shipped'
 when shipped>0 then 'partially_shipped'
 when exists(select 1 from public.ripening_allocations a join public.ripening_lots l on l.id=a.ripening_lot_id
 where a.order_id=order_value and l.status in ('in_progress','completed')) then 'in_progress' else 'confirmed' end,version=version+1,updated_by=actor
 where id=order_value returning * into new_order;
 insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
 values('order',order_value,'transition',to_jsonb(old_order),to_jsonb(new_order),reason_value,actor,correlation);
 perform private.project_shipping_task(order_value,actor,reason_value,correlation);
 new_status:=case when new_order.status='shipped' then 'completed' else 'pending' end;
 for t in select * from public.work_tasks where order_id=order_value and task_type='shipping' and managed_by_planning for update loop
   if t.status is distinct from new_status then
     update public.work_tasks set status=new_status,completed_at=case when new_status='completed' then statement_timestamp() end,
       completed_by=case when new_status='completed' then worker_value end,updated_by=actor where id=t.id;
     insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
     select 'work_task',id,'transition',to_jsonb(t),to_jsonb(w),reason_value,actor,correlation from public.work_tasks w where id=t.id;
   end if;
 end loop;
end;
$$;

create function private.shipment_action(fn text,input_value jsonb,actor uuid,correlation uuid,operation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.orders%rowtype; s public.shipments%rowtype; c public.containers%rowtype;
 elem jsonb; line public.shipment_lines%rowtype; event public.inventory_events%rowtype;
 target uuid; worker uuid; at_value timestamptz; expected bigint; amount numeric; total numeric:=0;
 lines_value jsonb; normalized_lines jsonb:='[]'::jsonb; seen uuid[]:=array[]::uuid[]; lot_id uuid; lot_amount numeric; allocated numeric;
 reason_value text; notes_value text; cust jsonb;
begin
 perform pg_advisory_xact_lock(53,0);
 reason_value:=private.rpc_input_text(input_value,'reason',true);
 if fn='shipment_confirm' then
   perform private.customer_order_validate_keys(input_value,array['order_id','expected_order_version','shipped_at','worker_id','checked','lines','notes','reason']);
   target:=private.rpc_input_uuid(input_value,'order_id',true);
   expected:=private.rpc_input_positive_int(input_value,'expected_order_version',true);
   worker:=private.rpc_input_uuid(input_value,'worker_id',true);
   notes_value:=private.rpc_input_text(input_value,'notes',false);
   if input_value->'checked' is distinct from 'true'::jsonb then
     perform private.rpc_fail('KW400','CONFIRMATION_REQUIRED','出荷内容の確認が必要です。',jsonb_build_object('field','checked'));
   end if;
   at_value:=case when not(input_value ? 'shipped_at') then statement_timestamp()
     else private.ripening_timestamp(input_value,'shipped_at') end;
   if at_value is null or not isfinite(at_value) or at_value>statement_timestamp() then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷日時は現在以前を指定してください。',jsonb_build_object('field','shipped_at'));
   end if;
   if not exists(select 1 from public.workers where id=worker and is_active) then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','有効な作業者を指定してください。',jsonb_build_object('field','worker_id'));
   end if;
   select * into o from public.orders where id=target for update;
   if not found or o.status not in ('confirmed','in_progress','partially_shipped') then
     perform private.rpc_fail('KW409','ORDER_UNAVAILABLE','この受注は出荷できません。',null);
   end if;
   if o.version<>expected then
     perform private.rpc_fail('KW409','CONFLICT_STALE','受注が更新されています。再読込してください。',jsonb_build_object('version',o.version));
   end if;
   lines_value:=input_value->'lines';
   if jsonb_typeof(lines_value) is distinct from 'array' then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷明細を指定してください。',jsonb_build_object('field','lines'));
   end if;
   if jsonb_array_length(lines_value) not between 1 and 100 then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','明細は1〜100件で指定してください。',null);
   end if;
   for elem in select value from jsonb_array_elements(lines_value) loop
     if jsonb_typeof(elem) is distinct from 'object' then
       perform private.rpc_fail('KW400','VALIDATION_FAILED','明細はオブジェクトで指定してください。',jsonb_build_object('field','lines'));
     end if;
     perform private.customer_order_validate_keys(elem,array['container_id','expected_version','shipped_weight_kg']);
     target:=private.rpc_input_uuid(elem,'container_id',true);
     expected:=private.rpc_input_positive_int(elem,'expected_version',true);
     amount:=private.rpc_input_weight(elem,'shipped_weight_kg',true,false);
     if target=any(seen) then
       perform private.rpc_fail('KW400','VALIDATION_FAILED','同じコンテナを重複指定できません。',null);
     end if;
     seen:=array_append(seen,target); total:=total+amount;
     normalized_lines:=normalized_lines||jsonb_build_array(jsonb_build_object('container_id',target,'expected_version',expected,'shipped_weight_kg',amount));
   end loop;
   lines_value:=normalized_lines;
   if total>o.ordered_weight_kg-private.shipped_weight(o.id) then
     perform private.rpc_fail('KW400','ORDER_WEIGHT_EXCEEDED','受注の未出荷量を超えています。',null);
   end if;
   -- Stable lock order; the planning advisory lock also serializes allocation changes.
   perform 1 from public.containers where id=any(seen) order by id for update;
   for elem in select value from jsonb_array_elements(lines_value) loop
     select * into c from public.containers where id=(elem->>'container_id')::uuid;
     if not found or c.ripening_lot_id is null or row(c.variety_id,c.grade_id) is distinct from row(o.variety_id,o.grade_id) then
       perform private.rpc_fail('KW400','CONTAINER_UNAVAILABLE','対象の追熟コンテナを指定してください。',null);
     end if;
     if c.version<>(elem->>'expected_version')::bigint then
       perform private.rpc_fail('KW409','CONFLICT_STALE','コンテナが更新されています。再読込してください。',jsonb_build_object('container_id',c.id,'version',c.version));
     end if;
     if c.best_before_at is null or c.shippable_until is null then
       perform private.rpc_fail('KW400','DEADLINE_UNSET','出荷期限が設定されていません。',null);
     end if;
     if least(c.best_before_at,c.shippable_until)<=greatest(statement_timestamp(),at_value) or c.status='expired' then
       perform private.rpc_fail('KW400','CONTAINER_EXPIRED','出荷期限を過ぎています。',null);
     end if;
     if c.status<>'shippable' then
       perform private.rpc_fail('KW400','CONTAINER_UNAVAILABLE','出荷可能なコンテナではありません。',null);
     end if;
     if (elem->>'shipped_weight_kg')::numeric>c.current_weight_kg-c.reserved_weight_kg then
       perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','コンテナの使用可能残量を超えています。',null);
     end if;
   end loop;
   for lot_id in select distinct ripening_lot_id from public.containers where id=any(seen) loop
     select sum((e.value->>'shipped_weight_kg')::numeric) into lot_amount
       from jsonb_array_elements(lines_value) e join public.containers cc on cc.id=(e.value->>'container_id')::uuid
       where cc.ripening_lot_id=lot_id;
     select allocated_weight_kg into allocated from public.ripening_allocations where ripening_lot_id=lot_id and order_id=o.id;
     if allocated is null or lot_amount>allocated-private.shipped_weight(o.id,lot_id) then
       perform private.rpc_fail('KW400','ALLOCATION_UNAVAILABLE','この受注に割り当てられた残量を超えています。',null);
     end if;
   end loop;
   select jsonb_build_object('customer_id',id,'customer_code',customer_code,'name',name,'nickname',nickname)
     into cust from public.customers where id=o.customer_id;
   insert into public.shipments(display_id,order_id,shipped_at,shipped_by,customer_snapshot,shipping_destination_snapshot,
     operation_id,correlation_id,reason,notes,created_by,updated_by)
   values(private.next_display_id('出荷',extract(year from at_value at time zone 'Asia/Tokyo')::integer),o.id,at_value,worker,
     cust,o.shipping_destination_snapshot,operation,correlation,reason_value,notes_value,actor,actor) returning * into s;
   for elem in select value from jsonb_array_elements(lines_value) order by value->>'container_id' loop
     select * into strict c from public.containers where id=(elem->>'container_id')::uuid;
     amount:=(elem->>'shipped_weight_kg')::numeric;
     insert into public.shipment_lines(shipment_id,container_id,shipped_weight_kg,created_by)
       values(s.id,c.id,amount,actor) returning * into line;
     insert into public.inventory_events(container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
       shipment_line_id,operation_id,correlation_id,occurred_at,reason,created_by)
       values(c.id,'shipment',-amount,c.current_weight_kg,c.current_weight_kg-amount,line.id,operation,correlation,at_value,reason_value,actor);
   end loop;
 elsif fn='shipment_cancel' then
   perform private.customer_order_validate_keys(input_value,array['shipment_id','expected_version','reason']);
   target:=private.rpc_input_uuid(input_value,'shipment_id',true);
   expected:=private.rpc_input_positive_int(input_value,'expected_version',true);
   select * into s from public.shipments where id=target for update;
   if not found or s.status<>'confirmed' then
     perform private.rpc_fail('KW409','SHIPMENT_UNAVAILABLE','この出荷は取消できません。',null);
   end if;
   if s.version<>expected then
     perform private.rpc_fail('KW409','CONFLICT_STALE','出荷が更新されています。',jsonb_build_object('version',s.version));
   end if;
   select * into strict o from public.orders where id=s.order_id for update;
   if o.status='cancelled' then
     perform private.rpc_fail('KW409','ORDER_UNAVAILABLE','キャンセル済み受注の出荷は取消できません。',null);
   end if;
   perform 1 from public.containers c2 where id in (select container_id from public.shipment_lines where shipment_id=s.id) order by id for update;
   for line in select * from public.shipment_lines where shipment_id=s.id order by container_id loop
     select * into strict c from public.containers where id=line.container_id;
     if c.current_weight_kg+line.shipped_weight_kg>c.original_weight_kg then
       perform private.rpc_fail('KW409','INVENTORY_CONFLICT','取消後の重量が元の重量を超えます。確認してください。',null);
     end if;
   end loop;
   update public.shipments set status='cancelled',cancelled_at=greatest(statement_timestamp(),shipped_at),cancelled_by=actor,
     cancellation_reason=reason_value,cancellation_operation_id=operation,correlation_id=correlation,version=version+1,updated_by=actor where id=s.id;
   for line in select * from public.shipment_lines where shipment_id=s.id order by container_id loop
     select * into strict c from public.containers where id=line.container_id;
     select * into strict event from public.inventory_events where shipment_line_id=line.id and event_type='shipment';
     insert into public.inventory_events(container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
       shipment_line_id,reverses_event_id,operation_id,correlation_id,occurred_at,reason,created_by)
     values(c.id,'shipment_cancel',line.shipped_weight_kg,c.current_weight_kg,c.current_weight_kg+line.shipped_weight_kg,
       line.id,event.id,operation,correlation,greatest(statement_timestamp(),event.occurred_at),reason_value,actor);
   end loop;
 else raise exception 'unsupported shipment operation'; end if;
 perform private.refresh_shipped_order(o.id,actor,correlation,reason_value,s.shipped_by);
 return public.shipment_get(s.id)||jsonb_build_object('order',public.order_get(o.id));
end;
$$;
create or replace function private.shipment_rpc(function_name_value text, req jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  raw_correlation text; correlation_value uuid; key_value uuid; input_value jsonb;
  actor_value uuid; hash_value text; outcome_value text; stored_value jsonb; envelope_value jsonb;
  code_value text; message_value text; details_value text; state_value text;
begin
  if req is null or jsonb_typeof(req)<>'object' then
    return private.rpc_error_envelope(null,'business','VALIDATION_FAILED',
      '要求の形式が正しくありません。',jsonb_build_object('field','req','reason','invalid_type'));
  end if;
  raw_correlation:=req->'meta'->>'correlation_id';
  correlation_value:=private.rpc_try_uuid_v4(raw_correlation);
  key_value:=private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key');
  input_value:=req->'input';
  if correlation_value is null then
    return private.rpc_error_envelope(raw_correlation,'business','VALIDATION_FAILED',
      'correlation_id が正しくありません。',jsonb_build_object('field','meta.correlation_id','reason','invalid_format'));
  end if;
  if key_value is null then
    return private.rpc_error_envelope(raw_correlation,'business','VALIDATION_FAILED',
      'idempotency_key が正しくありません。',jsonb_build_object('field','meta.idempotency_key','reason','invalid_format'));
  end if;
  if input_value is null or jsonb_typeof(input_value)<>'object' then
    return private.rpc_error_envelope(raw_correlation,'business','VALIDATION_FAILED',
      'input が正しくありません。',jsonb_build_object('field','input','reason','invalid_type'));
  end if;
  actor_value:=auth.uid();
  if actor_value is null then
    return private.rpc_error_envelope(raw_correlation,'auth','AUTH_REQUIRED','ログインが必要です。',null);
  end if;
  if not private.current_user_is_active() then
    return private.rpc_error_envelope(raw_correlation,'auth','AUTH_FORBIDDEN',
      '有効な利用者だけが操作できます。',null);
  end if;
  hash_value:=encode(sha256(convert_to(function_name_value||':'||input_value::text,'utf8')),'hex');
  select claim_outcome,stored_response into outcome_value,stored_value
  from private.rpc_claim_idempotency(function_name_value,key_value,hash_value,actor_value);
  if outcome_value='replay' then
    return stored_value||jsonb_build_object('correlation_id',raw_correlation,'idempotent_replay',true);
  elsif outcome_value='reused' then
    return private.rpc_error_envelope(raw_correlation,'conflict','IDEMPOTENCY_KEY_REUSED',
      '同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。',null);
  end if;
  begin
    envelope_value:=private.rpc_success_envelope(raw_correlation,
      private.shipment_action(function_name_value,input_value,actor_value,correlation_value,key_value));
  exception when sqlstate 'KW400' or sqlstate 'KW409' then
    get stacked diagnostics code_value=message_text,message_value=pg_exception_hint,
      details_value=pg_exception_detail,state_value=returned_sqlstate;
    envelope_value:=private.rpc_error_envelope(raw_correlation,
      case state_value when 'KW409' then 'conflict' else 'business' end,
      code_value,message_value,nullif(details_value,'')::jsonb);
  end;
  perform private.rpc_store_idempotency(key_value,envelope_value);
  return envelope_value;
end;
$$;

do $$
declare function_name text;
begin
  foreach function_name in array array['shipment_confirm','shipment_cancel']
  loop
    execute format($fn$
      create or replace function public.%1$I(req jsonb) returns jsonb
      language sql security definer set search_path = '' as $body$
        select private.rpc_log_response(%2$L,auth.uid(),
          private.rpc_try_uuid_v4(req->'meta'->>'correlation_id'),
          private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key'),
          private.shipment_rpc(%2$L,req))
      $body$;
    $fn$,function_name,function_name);
    execute format('revoke all on function public.%I(jsonb) from public,anon',function_name);
    execute format('grant execute on function public.%I(jsonb) to authenticated,service_role',function_name);
  end loop;
end;
$$;
create or replace function private.apply_inventory_event()
returns trigger language plpgsql set search_path = '' as $$
declare
  c public.containers%rowtype;
  original public.inventory_events%rowtype;
  line public.shipment_lines%rowtype;
  shipment public.shipments%rowtype;
  target_order public.orders%rowtype;
begin
  if new.shipment_line_id is not null then
    select * into strict line from public.shipment_lines where id = new.shipment_line_id;
    select * into strict shipment from public.shipments where id = line.shipment_id for update;
    select * into strict target_order from public.orders where id = shipment.order_id for no key update;
  end if;
  select * into strict c from public.containers where id = new.container_id for no key update;
  if c.current_weight_kg <> new.before_weight_kg then
    raise exception 'inventory event balance is stale' using errcode = '23514';
  end if;
  if new.after_weight_kg < c.reserved_weight_kg or new.after_weight_kg > c.original_weight_kg then
    raise exception 'inventory event exceeds available weight or capacity' using errcode = '23514';
  end if;
  if new.event_type in ('shipment', 'shipment_cancel') then
    if line.container_id <> c.id or line.shipped_weight_kg <> abs(new.quantity_delta_kg) then
      raise exception 'shipment event does not match line' using errcode = '23514';
    end if;
    if c.ripening_lot_id is null or
        row(c.variety_id, c.grade_id) is distinct from row(target_order.variety_id, target_order.grade_id) then
      raise exception 'shipment container product does not match order' using errcode = '23514';
    end if;
  end if;
  if new.event_type = 'shipment' then
    if shipment.status <> 'confirmed' or target_order.status in ('draft', 'cancelled')
        or c.status <> 'shippable' or c.best_before_at is null or c.shippable_until is null
        or least(c.best_before_at, c.shippable_until) <= greatest(statement_timestamp(), shipment.shipped_at) then
      raise exception 'container is not available for shipment' using errcode = '23514';
    end if;
    if (select coalesce(sum(l.shipped_weight_kg), 0)
        from public.shipment_lines l join public.shipments s on s.id = l.shipment_id
        where s.order_id = shipment.order_id and s.status = 'confirmed') > target_order.ordered_weight_kg then
      raise exception 'shipment exceeds ordered weight' using errcode = '23514';
    end if;
  elsif new.event_type = 'shipment_cancel' then
    select * into strict original from public.inventory_events where id = new.reverses_event_id;
    if shipment.status <> 'cancelled' or original.event_type <> 'shipment'
        or original.container_id <> c.id or original.shipment_line_id <> new.shipment_line_id
        or original.quantity_delta_kg <> -new.quantity_delta_kg
        or new.occurred_at < original.occurred_at then
      raise exception 'invalid shipment reversal' using errcode = '23514';
    end if;
  elsif new.event_type = 'ripening_in' then
    if c.ripening_lot_id is distinct from new.ripening_lot_id then
      raise exception 'ripening input does not match output container' using errcode = '23514';
    end if;
  elsif new.event_type = 'ripening_out' then
    if not exists (select 1 from public.inventory_reservations r
      where r.container_id = c.id and r.ripening_lot_id = new.ripening_lot_id
      and r.status = 'consumed' and r.reserved_weight_kg = -new.quantity_delta_kg) then
      raise exception 'ripening output requires consumed reservation' using errcode = '23514';
    end if;
  end if;
  update public.containers set
    current_weight_kg = new.after_weight_kg,
    version = version + 1,
    status = case
      when new.event_type = 'shipment' and new.after_weight_kg = 0 then 'shipped'
      when new.event_type = 'shipment_cancel' and c.status in ('shipped','shippable') then
        case when c.best_before_at <= statement_timestamp() then 'expired' else 'shippable' end
      else status end,
    expired_at = case when new.event_type = 'shipment_cancel' and c.status in ('shipped','shippable')
      and c.best_before_at <= statement_timestamp() then statement_timestamp() else expired_at end
  where id = c.id;
  insert into public.change_history (
    entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
  ) select 'container', c.id, 'update', to_jsonb(c), to_jsonb(updated),
    new.reason, new.created_by, coalesce(new.correlation_id,new.operation_id)
    from public.containers updated where updated.id = c.id;
  return new;
end;
$$;
create or replace function private.record_s3_history()
returns trigger language plpgsql set search_path = '' as $$
declare
  entity_name text;
  data jsonb := to_jsonb(new);
  prior jsonb;
begin
  entity_name := case tg_table_name
    when 'ripening_work_results' then 'ripening_work_result'
    when 'shipments' then 'shipment'
    when 'shipment_lines' then 'shipment_line'
    else 'inventory_event' end;
  if tg_table_name='shipment_lines' then
    select data||jsonb_build_object('operation_id',s.operation_id,'correlation_id',s.correlation_id,'reason',s.reason)
      into data from public.shipments s where s.id=(data->>'shipment_id')::uuid;
  end if;
  if tg_op = 'UPDATE' then prior := to_jsonb(old); end if;
  insert into public.change_history (
    entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
  ) values (
    entity_name, new.id, case when tg_op = 'INSERT' then 'create' else 'update' end,
    prior, data,
    coalesce(nullif(data->>'cancellation_reason', ''), nullif(data->>'reason', ''),
      nullif(data->>'notes', ''), entity_name || ' ' || lower(tg_op)),
    coalesce(auth.uid(), (data->>'updated_by')::uuid, new.created_by),
    coalesce((data->>'correlation_id')::uuid,(data->>'operation_id')::uuid)
  );
  return null;
end;
$$;

revoke all on function private.shipped_weight(uuid,uuid),private.remaining_lot_use(uuid),
 private.refresh_shipped_order(uuid,uuid,uuid,text,uuid),private.shipment_action(text,jsonb,uuid,uuid,uuid),private.shipment_rpc(text,jsonb)
 from public,anon,authenticated;
revoke all on function public.shipment_get(uuid),public.shipment_list(uuid),public.shipment_container_list(uuid),public.shipment_inventory_list() from public,anon;
grant execute on function public.shipment_get(uuid),public.shipment_list(uuid),public.shipment_container_list(uuid),public.shipment_inventory_list() to authenticated,service_role;
commit;
