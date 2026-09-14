begin;

-- Only the privileged atomic RPC can open this transaction-scoped transfer gate.
create table private.board_order_transfer (
  transaction_id bigint primary key,
  lot_id uuid not null,
  order_id uuid not null
);
revoke all on private.board_order_transfer from public,anon,authenticated,service_role;

create or replace function private.apply_ripening_allocation_delta()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  allocation_lot_value uuid;
  lot_status text;
  lot_variety_id uuid;
  lot_grade_id uuid;
  lot_delta numeric := 0;
  order_delta numeric := 0;
  order_row public.orders%rowtype;
begin
  allocation_lot_value := case when tg_op = 'DELETE' then old.ripening_lot_id else new.ripening_lot_id end;

  if tg_op = 'UPDATE' and new.ripening_lot_id <> old.ripening_lot_id then
    raise exception 'ripening allocation cannot move between lots' using errcode = '23514';
  end if;

  select status, variety_id, grade_id
  into lot_status, lot_variety_id, lot_grade_id
  from public.ripening_lots
  where id = allocation_lot_value
  for update;

  if lot_status <> 'draft' and not exists (
    select 1 from private.board_order_transfer t
    where t.transaction_id=txid_current() and t.lot_id=allocation_lot_value
      and (
        (tg_op='INSERT' and new.allocation_type='order' and new.order_id=t.order_id)
        or (tg_op='DELETE' and old.allocation_type='reserve')
        or (tg_op='UPDATE' and old.allocation_type='reserve'
          and new.allocation_type='reserve' and new.allocated_weight_kg<old.allocated_weight_kg)
      )
  ) then
    raise exception 'ripening allocations can only change while lot is draft' using errcode = '23514';
  end if;

  lot_delta :=
    (case when tg_op <> 'DELETE' then new.allocated_weight_kg else 0 end)
    - (case when tg_op <> 'INSERT' then old.allocated_weight_kg else 0 end);

  update public.ripening_lots
  set allocated_weight_kg = allocated_weight_kg + lot_delta
  where id = allocation_lot_value
    and allocated_weight_kg + lot_delta between 0 and total_weight_kg;

  if not found then
    raise exception 'ripening allocation exceeds lot weight' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.order_id is distinct from old.order_id then
    raise exception 'allocation order cannot be changed' using errcode = '23514';
  end if;

  if tg_op <> 'DELETE' and new.allocation_type = 'order' then
    select * into order_row from public.orders where id = new.order_id for update;
    if not found then
      raise exception 'order not found' using errcode = '23503';
    end if;
    if order_row.status not in ('confirmed', 'in_progress', 'partially_shipped') then
      raise exception 'order is not available for ripening allocation' using errcode = '23514';
    end if;
    if row(order_row.variety_id, order_row.grade_id)
      is distinct from row(lot_variety_id, lot_grade_id) then
      raise exception 'order product does not match ripening lot' using errcode = '23514';
    end if;
  end if;

  if tg_op <> 'INSERT' and old.allocation_type = 'order' then
    order_delta := order_delta - old.allocated_weight_kg;
  end if;
  if tg_op <> 'DELETE' and new.allocation_type = 'order' then
    order_delta := order_delta + new.allocated_weight_kg;
  end if;

  if order_delta <> 0 then
    update public.orders
    set allocated_weight_kg = allocated_weight_kg + order_delta
    where id = coalesce(new.order_id, old.order_id)
      and allocated_weight_kg + order_delta between 0 and ordered_weight_kg;
    if not found then
      raise exception 'order allocation exceeds ordered weight' using errcode = '23514';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;


create function private.board_order_candidates(input_value jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ship_date date; ship_at timestamptz; variety uuid; grade uuid; weight numeric; result jsonb;
begin
  ship_date:=private.rpc_input_date(input_value,'scheduled_ship_date',true);
  variety:=private.rpc_input_uuid(input_value,'variety_id',true);
  grade:=private.rpc_input_uuid(input_value,'grade_id',true);
  weight:=private.rpc_input_weight(input_value,'ordered_weight_kg',true,false);
  ship_at:=(ship_date+time '09:00') at time zone 'Asia/Tokyo';
  if ship_at<=statement_timestamp() then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷予定日は今後の日付を指定してください。');
  end if;
  if not exists(select 1 from public.varieties where id=variety and is_active)
    or not exists(select 1 from public.grades where id=grade and is_active) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','有効な品種・等級を指定してください。');
  end if;
  with cold as (
    select 'container'::text as kind,c.id,c.display_id,'sorted'::text as stage,
      c.current_weight_kg-c.reserved_weight_kg as available_weight_kg,
      ship_at-(r.ethylene_hours*interval '1 hour')-(r.rest_days*interval '24 hours') as planned_ethylene_at,
      ship_at as planned_completion_at,c.location_id,c.display_id as container_ids,
      md5(concat_ws('/',c.current_weight_kg,c.reserved_weight_kg,c.status,r.id,r.version)) as version
    from public.containers c
    join public.sorting_results s on s.id=c.sorting_result_id
    join public.receiving_lots receiving on receiving.id=s.receiving_lot_id
    join public.ripening_rules r on r.variety_id=c.variety_id
      and r.harvest_month=extract(month from receiving.received_on) and r.is_active
    where c.status='cold_storage' and not c.needs_review and c.variety_id=variety and c.grade_id=grade
      and c.current_weight_kg-c.reserved_weight_kg>=weight
      and ship_at-(r.ethylene_hours*interval '1 hour')-(r.rest_days*interval '24 hours')>=statement_timestamp()
  ), lots as (
    select l.*,
      case when l.status='confirmed' then
        (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations
          where ripening_lot_id=l.id and status='active')
      else
        (select coalesce(sum(current_weight_kg),0) from public.containers
          where ripening_lot_id=l.id and status in ('ethylene_processing','resting','awaiting_ripeness_check','shippable'))
      end as physical,
      (select coalesce(sum(allocated_weight_kg),0) from public.ripening_allocations
        where ripening_lot_id=l.id and allocation_type='reserve') as reserve,
      (select coalesce(sum(greatest(0,a.allocated_weight_kg-private.shipped_weight(a.order_id,l.id))),0)
        from public.ripening_allocations a join public.orders o on o.id=a.order_id
        where a.ripening_lot_id=l.id and o.status not in ('cancelled','shipped')) as committed
    from public.ripening_lots l
    where l.variety_id=variety and l.grade_id=grade
      and l.status in ('confirmed','in_progress','completed') and not l.needs_review
      and l.calculated_rest_end_at<=ship_at
      and l.calculated_shippable_until is not null and l.calculated_best_before_at is not null
      and (l.status<>'confirmed' or not exists(
        select 1 from public.inventory_reservations r join public.containers c on c.id=r.container_id
        where r.ripening_lot_id=l.id and r.status='active'
          and (c.needs_review or c.status<>'cold_storage' or c.current_weight_kg<c.reserved_weight_kg)))
      and least(l.calculated_shippable_until,l.calculated_best_before_at)>ship_at
      and not exists(select 1 from public.containers c where c.ripening_lot_id=l.id
        and c.current_weight_kg>0 and (c.needs_review or c.status='expired'))
      and not exists(select 1 from public.containers c where c.ripening_lot_id=l.id and c.status='shippable'
        and (c.shippable_until is null or c.best_before_at is null
          or least(c.shippable_until,c.best_before_at)<=ship_at))
  ), ready as (
    select 'lot'::text as kind,l.id,l.display_id,
      case when l.status='confirmed' then 'sorted'
        when exists(select 1 from public.containers where ripening_lot_id=l.id and status='ethylene_processing') then 'ripening'
        when exists(select 1 from public.containers where ripening_lot_id=l.id and status in ('resting','awaiting_ripeness_check')) then 'resting'
        else 'shippable' end as stage,
      least(l.reserve,greatest(0,l.physical-l.committed)) as available_weight_kg,
      l.planned_ethylene_at,l.calculated_rest_end_at as planned_completion_at,
      l.storage_location_id as location_id,
      case when l.status='confirmed' then
        (select string_agg(c.display_id,'、' order by c.display_id) from public.inventory_reservations r
          join public.containers c on c.id=r.container_id where r.ripening_lot_id=l.id and r.status='active')
      else (select string_agg(display_id,'、' order by display_id) from public.containers
        where ripening_lot_id=l.id and current_weight_kg>0) end as container_ids,
      md5(concat_ws('/',l.version,l.physical,l.reserve,l.committed,l.calculated_rest_end_at,
        l.calculated_shippable_until,l.calculated_best_before_at)) as version
    from lots l where least(l.reserve,greatest(0,l.physical-l.committed))>=weight
  ), candidates as (select * from cold union all select * from ready)
  select coalesce(jsonb_agg(to_jsonb(candidates) order by stage,display_id),'[]'::jsonb) into result from candidates;
  return result;
end;
$$;
revoke all on function private.board_order_candidates(jsonb) from public,anon,authenticated;

create function public.board_order_candidates(input_value jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
  if not private.current_user_has_role('administrator') then
    raise insufficient_privilege using message='管理者だけが候補を検索できます。';
  end if;
  return private.board_order_candidates(input_value);
end;
$$;
revoke all on function public.board_order_candidates(jsonb) from public,anon;
grant execute on function public.board_order_candidates(jsonb) to authenticated,service_role;

create function private.board_order_action(input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate jsonb; order_data jsonb; plan_data jsonb; source_id uuid; kind text;
  qty numeric; remaining numeric; use_qty numeric; row_value public.ripening_allocations%rowtype;
  lot public.ripening_lots%rowtype; before_value jsonb; after_value jsonb; entry record;
  old_value jsonb; new_value jsonb; operation text;
begin
  perform private.customer_order_validate_keys(input_value,array[
    'scheduled_ship_date','variety_id','grade_id','ordered_weight_kg',
    'candidate_kind','candidate_id','candidate_version','customer_id','shipping_destination_id',
    'storage_location_id','assigned_worker_id']);
  perform pg_advisory_xact_lock(53,0);
  kind:=private.rpc_input_text(input_value,'candidate_kind',true);
  source_id:=private.rpc_input_uuid(input_value,'candidate_id',true);
  qty:=private.rpc_input_weight(input_value,'ordered_weight_kg',true,false);
  if kind='container' then
    perform 1 from public.containers where id=source_id for update;
    -- Prevent changing the duration/master between candidate validation and plan creation.
    perform 1 from public.ripening_rules where is_active
      and variety_id=private.rpc_input_uuid(input_value,'variety_id',true) for share;
  elsif kind='lot' then
    perform 1 from public.ripening_lots where id=source_id for update;
    perform 1 from public.containers where ripening_lot_id=source_id order by id for update;
    perform 1 from public.ripening_allocations where ripening_lot_id=source_id order by id for update;
  else
    perform private.rpc_fail('KW400','VALIDATION_FAILED','候補の種類が正しくありません。');
  end if;
  select value into candidate from jsonb_array_elements(private.board_order_candidates(input_value))
    where value->>'kind'=kind and value->>'id'=source_id::text;
  if candidate is null or candidate->>'version' is distinct from
      private.rpc_input_text(input_value,'candidate_version',true) then
    perform private.rpc_fail('KW409','INVENTORY_UNAVAILABLE','在庫や計画が更新されています。条件を再検索してください。');
  end if;
  order_data:=private.customer_order_action('order_register',jsonb_build_object(
    'customer_id',input_value->'customer_id','shipping_destination_id',input_value->'shipping_destination_id',
    'ordered_date',to_char(statement_timestamp() at time zone 'Asia/Tokyo','YYYY-MM-DD'),
    'scheduled_ship_date',input_value->'scheduled_ship_date',
    'variety_id',input_value->'variety_id','grade_id',input_value->'grade_id',
    'ordered_weight_kg',qty),actor,correlation);
  order_data:=private.customer_order_action('order_confirm',jsonb_build_object(
    'order_id',order_data->'id','expected_version',order_data->'version','reason','工程ボードから同時登録'),actor,correlation);
  if kind='container' then
    plan_data:=private.ripening_plan_action('ripening_plan_register',jsonb_build_object(
      'variety_id',input_value->'variety_id','grade_id',input_value->'grade_id',
      'total_weight_kg',qty,'storage_location_id',input_value->'storage_location_id',
      'assigned_worker_id',input_value->'assigned_worker_id',
      'planned_ethylene_at',candidate->'planned_ethylene_at','planned_completion_at',candidate->'planned_completion_at',
      'allocations',jsonb_build_array(jsonb_build_object('allocation_type','order','order_id',order_data->'id','allocated_weight_kg',qty)),
      'reservations',jsonb_build_array(jsonb_build_object('container_id',source_id,'reserved_weight_kg',qty))
    ),actor,correlation);
    plan_data:=private.ripening_plan_action('ripening_plan_confirm',jsonb_build_object(
      'ripening_lot_id',plan_data->'id','expected_version',plan_data->'version','reason','工程ボードから同時登録'),actor,correlation);
  else
    select * into strict lot from public.ripening_lots where id=source_id;
    before_value:=private.ripening_audit_snapshot(lot.id,array[(order_data->>'id')::uuid],array[]::uuid[]);
    insert into private.board_order_transfer values(txid_current(),lot.id,(order_data->>'id')::uuid);
    remaining:=qty;
    for row_value in select * from public.ripening_allocations
      where ripening_lot_id=lot.id and allocation_type='reserve' order by id for update loop
      exit when remaining=0;
      use_qty:=least(remaining,row_value.allocated_weight_kg);
      if use_qty=row_value.allocated_weight_kg then
        delete from public.ripening_allocations where id=row_value.id;
      else
        update public.ripening_allocations set allocated_weight_kg=allocated_weight_kg-use_qty,
          updated_by=actor where id=row_value.id;
      end if;
      remaining:=remaining-use_qty;
    end loop;
    if remaining<>0 then
      perform private.rpc_fail('KW409','INVENTORY_UNAVAILABLE','予備在庫が不足しています。再検索してください。');
    end if;
    insert into public.ripening_allocations(ripening_lot_id,allocation_type,order_id,allocated_weight_kg,created_by,updated_by)
      values(lot.id,'order',(order_data->>'id')::uuid,qty,actor,actor);
    delete from private.board_order_transfer where transaction_id=txid_current();
    update public.ripening_lots set version=version+1,updated_by=actor where id=lot.id;
    if lot.status in ('in_progress','completed') then
      update public.orders set status='in_progress',version=version+1,updated_by=actor where id=(order_data->>'id')::uuid;
    end if;
    perform private.project_ripening_tasks(lot.id,actor,'予備在庫を受注に割当',correlation);
    perform private.project_shipping_task((order_data->>'id')::uuid,actor,'予備在庫を受注に割当',correlation);
    after_value:=private.ripening_audit_snapshot(lot.id,array[(order_data->>'id')::uuid],array[]::uuid[]);
    for entry in select key from jsonb_object_keys(before_value||after_value) key loop
      old_value:=before_value->entry.key; new_value:=after_value->entry.key;
      if old_value is not distinct from new_value then continue; end if;
      operation:=case when old_value is null then 'create' when new_value is null then 'delete' else 'update' end;
      insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
        values(coalesce(new_value,old_value)->>'entity',(coalesce(new_value,old_value)->>'id')::uuid,
          operation,old_value->'data',coalesce(new_value->'data',jsonb_build_object('deleted',true)),
          '工程ボードから予備在庫を受注に割当',actor,correlation);
    end loop;
    plan_data:=public.ripening_plan_get(lot.id);
  end if;
  return jsonb_build_object('order_id',order_data->'id','order_number',order_data->'order_number',
    'ripening_lot_id',plan_data->'id','ripening_display_id',plan_data->'display_id','existing_plan',kind='lot');
end;
$$;
revoke all on function private.board_order_action(jsonb,uuid,uuid) from public,anon,authenticated;

create or replace function private.board_order_rpc(function_name_value text, req jsonb)
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
  if not private.current_user_has_role('administrator') then
    return private.rpc_error_envelope(raw_correlation,'auth','AUTH_FORBIDDEN',
      '顧客・受注の変更は管理者だけが行えます。',null);
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
      private.board_order_action(input_value,actor_value,correlation_value));
  exception when sqlstate 'KW400' or sqlstate 'KW409' then
    get stacked diagnostics code_value=message_text,message_value=pg_exception_hint,
      details_value=pg_exception_detail,state_value=returned_sqlstate;
    envelope_value:=private.rpc_error_envelope(raw_correlation,
      case state_value when 'KW409' then 'conflict' else 'business' end,
      code_value,message_value,nullif(details_value,'')::jsonb);
    when unique_violation then
    envelope_value:=private.rpc_error_envelope(raw_correlation,'business',
      case
        when function_name_value like 'customer_%' then 'CUSTOMER_DUPLICATE'
        when function_name_value like 'shipping_destination_%' then 'SHIPPING_DESTINATION_DUPLICATE'
        else 'ORDER_DUPLICATE'
      end,
      '同じ値のデータがすでに登録されています。',
      jsonb_build_object('reason','duplicate'));
  end;
  perform private.rpc_store_idempotency(key_value,envelope_value);
  return envelope_value;
end;
$$;

revoke all on function private.board_order_rpc(text,jsonb) from public,anon,authenticated;
create function public.board_order_confirm(req jsonb)
returns jsonb language sql security definer set search_path='' as $$
  select private.rpc_log_response('board_order_confirm',auth.uid(),
    private.rpc_try_uuid_v4(req->'meta'->>'correlation_id'),
    private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key'),
    private.board_order_rpc('board_order_confirm',req));
$$;
revoke all on function public.board_order_confirm(jsonb) from public,anon;
grant execute on function public.board_order_confirm(jsonb) to authenticated,service_role;
commit;
