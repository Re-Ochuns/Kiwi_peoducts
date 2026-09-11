begin;

-- Serialize the two S2 aggregates before either acquires order/lot row locks.
alter function private.customer_order_action(text,jsonb,uuid,uuid)
  rename to customer_order_action_without_planning_lock;
create function private.customer_order_action(fn text, input_value jsonb, actor uuid, correlation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(53, 0);
  return private.customer_order_action_without_planning_lock(fn,input_value,actor,correlation);
end;
$$;
revoke all on function private.customer_order_action(text,jsonb,uuid,uuid) from public,anon,authenticated;

create function private.ripening_timestamp(input_value jsonb, field_name text)
returns timestamptz language plpgsql set search_path = '' as $$
declare value_text text; result_value timestamptz;
begin
  value_text := private.rpc_input_text(input_value,field_name,true);
  if value_text !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$' then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','日時にはタイムゾーンを指定してください。',
      jsonb_build_object('field',field_name,'reason','invalid_format'));
  end if;
  begin
    result_value := value_text::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','日時が正しくありません。',
      jsonb_build_object('field',field_name,'reason','invalid_format'));
  end;
  if extract(year from result_value at time zone 'Asia/Tokyo') not between 2000 and 9999 then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','日時が範囲外です。',
      jsonb_build_object('field',field_name,'reason','out_of_range'));
  end if;
  return result_value;
end;
$$;

create function private.ripening_plan_input(input_value jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v uuid; g uuid; location_value uuid; worker_value uuid;
  weight_value numeric; start_value timestamptz; end_value timestamptz;
  line jsonb; field_name text; key_value text; seen text[]; sum_value numeric;
  line_weight numeric; order_value uuid; type_value text;
  normalized jsonb := '{}'::jsonb; normalized_lines jsonb; normalized_line jsonb;
begin
  v := private.rpc_input_uuid(input_value,'variety_id',true);
  g := private.rpc_input_uuid(input_value,'grade_id',true);
  location_value := private.rpc_input_uuid(input_value,'storage_location_id',true);
  worker_value := private.rpc_input_uuid(input_value,'assigned_worker_id',true);
  weight_value := private.rpc_input_weight(input_value,'total_weight_kg',true,false);
  start_value := private.ripening_timestamp(input_value,'planned_ethylene_at');
  end_value := private.ripening_timestamp(input_value,'planned_completion_at');
  if end_value < start_value then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','完了予定は注入予定以降にしてください。');
  end if;
  if not exists(select 1 from public.varieties where id=v and is_active for share)
    or not exists(select 1 from public.grades where id=g and is_active for share)
    or not exists(select 1 from public.storage_locations where id=location_value and is_active for share)
    or not exists(select 1 from public.workers where id=worker_value and is_active for share) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','参照マスターが見つからないか無効です。');
  end if;
  foreach field_name in array array['allocations','reservations'] loop
    if jsonb_typeof(input_value->field_name) is distinct from 'array'
      or jsonb_array_length(input_value->field_name)>100 then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','内訳・予約は100行以内の配列を指定してください。',
        jsonb_build_object('field',field_name,'reason','invalid_type'));
    end if;
    seen := array[]::text[]; sum_value := 0; normalized_lines := '[]'::jsonb;
    for line in select value from jsonb_array_elements(input_value->field_name) loop
      if jsonb_typeof(line)<>'object' then
        perform private.rpc_fail('KW400','VALIDATION_FAILED','行の形式が正しくありません。');
      end if;
      if field_name='allocations' then
        perform private.customer_order_validate_keys(line,
          array['allocation_type','order_id','allocated_weight_kg','notes']);
        type_value := private.rpc_input_text(line,'allocation_type',true);
        order_value := private.rpc_input_uuid(line,'order_id',false);
        if type_value not in ('order','reserve')
          or (type_value='order' and order_value is null)
          or (type_value='reserve' and order_value is not null) then
          perform private.rpc_fail('KW400','VALIDATION_FAILED','受注・予備の指定が正しくありません。');
        end if;
        key_value := coalesce(order_value::text,'reserve');
        line_weight := private.rpc_input_weight(line,'allocated_weight_kg',true,false);
        normalized_line := jsonb_build_object('allocation_type',type_value,
          'order_id',order_value,'allocated_weight_kg',line_weight);
      else
        perform private.customer_order_validate_keys(line,array['container_id','reserved_weight_kg','notes']);
        key_value := private.rpc_input_uuid(line,'container_id',true)::text;
        line_weight := private.rpc_input_weight(line,'reserved_weight_kg',true,false);
        normalized_line := jsonb_build_object('container_id',key_value::uuid,
          'reserved_weight_kg',line_weight);
      end if;
      normalized_line := normalized_line || jsonb_build_object('notes',private.rpc_input_text(line,'notes',false));
      normalized_lines := normalized_lines || jsonb_build_array(normalized_line);
      if key_value=any(seen) then
        perform private.rpc_fail('KW400','VALIDATION_FAILED','内訳・予約に重複があります。',
          jsonb_build_object('field',field_name,'reason','duplicate'));
      end if;
      seen := array_append(seen,key_value); sum_value := sum_value+line_weight;
    end loop;
    if sum_value>weight_value then
      perform private.rpc_fail('KW400','RIPENING_WEIGHT_MISMATCH','内訳・予約合計が追熟重量を超えています。',
        jsonb_build_object('field',field_name,'total_weight_kg',weight_value,'actual_weight_kg',sum_value));
    end if;
    normalized := normalized || jsonb_build_object(field_name,normalized_lines);
  end loop;
  return jsonb_build_object('variety_id',v,'grade_id',g,'total_weight_kg',weight_value,
    'storage_location_id',location_value,'assigned_worker_id',worker_value,
    'planned_ethylene_at',start_value,'planned_completion_at',end_value,
    'notes',private.rpc_input_text(input_value,'notes',false),
    'allocations',normalized->'allocations','reservations',normalized->'reservations');
end;
$$;

create function public.ripening_plan_get(ripening_lot_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select to_jsonb(l)||jsonb_build_object(
    'allocations',coalesce((select jsonb_agg(to_jsonb(a) order by a.id)
      from public.ripening_allocations a where a.ripening_lot_id=l.id),'[]'::jsonb),
    'reservations',coalesce((select jsonb_agg(to_jsonb(r) order by r.container_id)
      from public.inventory_reservations r where r.ripening_lot_id=l.id),'[]'::jsonb))
  from public.ripening_lots l where l.id=ripening_lot_id_value;
$$;

create function public.ripening_inventory_available()
returns table(container_id uuid,display_id text,variety_id uuid,grade_id uuid,
  current_weight_kg numeric,reserved_weight_kg numeric,available_weight_kg numeric)
language sql stable security invoker set search_path = '' as $$
  select c.id,c.display_id,c.variety_id,c.grade_id,c.current_weight_kg::numeric,
    c.reserved_weight_kg::numeric,(c.current_weight_kg-c.reserved_weight_kg)::numeric
  from public.containers c where c.status='cold_storage' order by c.display_id,c.id;
$$;

-- Snapshot only the affected aggregate and its old/new source rows.
create function private.ripening_audit_snapshot(lot_value uuid, orders_value uuid[], containers_value uuid[])
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_object_agg(entity||'/'||id::text,
    jsonb_build_object('entity',entity,'id',id,'data',data)),'{}'::jsonb)
  from (
    select 'ripening_lot' entity,id,to_jsonb(l) data from public.ripening_lots l where id=lot_value
    union all select 'ripening_allocation',id,to_jsonb(a) from public.ripening_allocations a where ripening_lot_id=lot_value
    union all select 'inventory_reservation',id,to_jsonb(r) from public.inventory_reservations r where ripening_lot_id=lot_value
    union all select 'order',id,to_jsonb(o) from public.orders o where id=any(orders_value)
    union all select 'container',id,to_jsonb(c) from public.containers c where id=any(containers_value)
  ) rows;
$$;

create function private.ripening_plan_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  lot_value uuid; lot_row public.ripening_lots%rowtype; data_value jsonb; line jsonb;
  before_value jsonb; after_value jsonb; entry record; old_row jsonb; new_row jsonb;
  orders_value uuid[]; containers_value uuid[]; reason_value text; expected bigint;
  source public.containers%rowtype; order_row public.orders%rowtype;
  requested numeric; operation_value text;
begin
  perform pg_advisory_xact_lock(53,0);
  if fn not in ('ripening_plan_register','ripening_plan_update','ripening_plan_confirm','ripening_plan_cancel') then
    raise exception 'unsupported ripening RPC';
  end if;
  if fn in ('ripening_plan_register','ripening_plan_update') then
    perform private.customer_order_validate_keys(input_value,
      case when fn='ripening_plan_register' then array[]::text[]
      else array['ripening_lot_id','expected_version'] end ||
      array['variety_id','grade_id','total_weight_kg','storage_location_id',
        'planned_ethylene_at','planned_completion_at','assigned_worker_id','notes',
        'allocations','reservations','reason']);
    data_value := private.ripening_plan_input(input_value);
  else
    perform private.customer_order_validate_keys(input_value,array['ripening_lot_id','expected_version','reason']);
  end if;
  reason_value := coalesce(private.rpc_input_text(input_value,'reason',fn<>'ripening_plan_register'),'追熟計画登録');
  if fn='ripening_plan_register' then
    lot_value := gen_random_uuid();
  else
    lot_value := private.rpc_input_uuid(input_value,'ripening_lot_id',true);
    expected := private.rpc_input_positive_int(input_value,'expected_version',true);
    select * into lot_row from public.ripening_lots where id=lot_value for update;
    if not found then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟計画が見つかりません。');
    end if;
    if lot_row.version<>expected or lot_row.status not in ('draft','confirmed')
      or (fn='ripening_plan_confirm' and lot_row.status<>'draft')
      or exists(select 1 from public.inventory_reservations where ripening_lot_id=lot_value and status='consumed') then
      perform private.rpc_fail('KW409','CONFLICT_STALE','計画が更新されたか作業が開始されています。',
        jsonb_build_object('current',to_jsonb(lot_row)));
    end if;
  end if;
  select coalesce(array_agg(distinct id),array[]::uuid[]) into orders_value from (
    select order_id id from public.ripening_allocations where ripening_lot_id=lot_value and order_id is not null
    union select (value->>'order_id')::uuid from jsonb_array_elements(data_value->'allocations')
      where value->>'order_id' is not null) ids;
  select coalesce(array_agg(distinct id),array[]::uuid[]) into containers_value from (
    select container_id id from public.inventory_reservations where ripening_lot_id=lot_value
    union select (value->>'container_id')::uuid from jsonb_array_elements(data_value->'reservations')) ids;
  perform 1 from public.orders where id=any(orders_value) order by id for update;
  perform 1 from public.containers where id=any(containers_value) order by id for update;
  before_value := private.ripening_audit_snapshot(lot_value,orders_value,containers_value);

  if fn='ripening_plan_register' then
    insert into public.ripening_lots(id,display_id,variety_id,grade_id,total_weight_kg,
      storage_location_id,planned_ethylene_at,planned_completion_at,assigned_worker_id,notes,created_by,updated_by)
    values(lot_value,private.next_display_id('追熟',extract(year from
      (data_value->>'planned_ethylene_at')::timestamptz at time zone 'Asia/Tokyo')::integer),
      (data_value->>'variety_id')::uuid,(data_value->>'grade_id')::uuid,
      (data_value->>'total_weight_kg')::numeric,(data_value->>'storage_location_id')::uuid,
      (data_value->>'planned_ethylene_at')::timestamptz,(data_value->>'planned_completion_at')::timestamptz,
      (data_value->>'assigned_worker_id')::uuid,data_value->>'notes',actor,actor);
  elsif fn in ('ripening_plan_update','ripening_plan_cancel') then
    update public.ripening_lots set status='draft',updated_by=actor where id=lot_value;
    delete from public.ripening_allocations where ripening_lot_id=lot_value;
    if fn='ripening_plan_cancel' then
      update public.inventory_reservations set status='released',released_at=now(),updated_by=actor
        where ripening_lot_id=lot_value and status='active';
      update public.ripening_lots set status='cancelled',needs_review=false,
        version=version+1,updated_by=actor where id=lot_value;
    else
      delete from public.inventory_reservations where ripening_lot_id=lot_value;
      update public.ripening_lots set
        variety_id=(data_value->>'variety_id')::uuid,grade_id=(data_value->>'grade_id')::uuid,
        total_weight_kg=(data_value->>'total_weight_kg')::numeric,
        storage_location_id=(data_value->>'storage_location_id')::uuid,
        assigned_worker_id=(data_value->>'assigned_worker_id')::uuid,
        planned_ethylene_at=(data_value->>'planned_ethylene_at')::timestamptz,
        planned_completion_at=(data_value->>'planned_completion_at')::timestamptz,
        notes=data_value->>'notes',needs_review=true,version=version+1,updated_by=actor where id=lot_value;
    end if;
  end if;

  if fn in ('ripening_plan_register','ripening_plan_update') then
    for line in select value from jsonb_array_elements(data_value->'allocations') loop
      requested := (line->>'allocated_weight_kg')::numeric;
      if line->>'allocation_type'='order' then
        select * into order_row from public.orders where id=(line->>'order_id')::uuid;
        if not found or order_row.status not in ('confirmed','in_progress','partially_shipped')
          or order_row.variety_id<>(data_value->>'variety_id')::uuid
          or order_row.grade_id<>(data_value->>'grade_id')::uuid
          or order_row.allocated_weight_kg+requested>order_row.ordered_weight_kg then
          perform private.rpc_fail('KW400','ORDER_UNAVAILABLE','受注の状態・品種・等級・未割当量を確認してください。',
            jsonb_build_object('order_id',line->>'order_id'));
        end if;
      end if;
      insert into public.ripening_allocations(ripening_lot_id,allocation_type,order_id,
        allocated_weight_kg,notes,created_by,updated_by)
      values(lot_value,line->>'allocation_type',(line->>'order_id')::uuid,requested,line->>'notes',actor,actor);
    end loop;
    for line in select value from jsonb_array_elements(data_value->'reservations') loop
      requested := (line->>'reserved_weight_kg')::numeric;
      select * into source from public.containers where id=(line->>'container_id')::uuid;
      if not found or source.status<>'cold_storage'
        or source.variety_id<>(data_value->>'variety_id')::uuid
        or source.grade_id<>(data_value->>'grade_id')::uuid
        or source.current_weight_kg-source.reserved_weight_kg<requested then
        perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','冷蔵在庫の状態・品種・等級・使用可能量を確認してください。',
          jsonb_build_object('container_id',line->>'container_id','requested_weight_kg',requested));
      end if;
      insert into public.inventory_reservations(ripening_lot_id,container_id,reserved_weight_kg,notes,created_by,updated_by)
      values(lot_value,source.id,requested,line->>'notes',actor,actor);
    end loop;
  elsif fn='ripening_plan_confirm' then
    -- Validate the persisted draft, including masters and orders changed since creation.
    perform private.ripening_plan_input(jsonb_build_object(
      'variety_id',lot_row.variety_id,'grade_id',lot_row.grade_id,'total_weight_kg',lot_row.total_weight_kg,
      'storage_location_id',lot_row.storage_location_id,'assigned_worker_id',lot_row.assigned_worker_id,
      'planned_ethylene_at',to_char(lot_row.planned_ethylene_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'planned_completion_at',to_char(lot_row.planned_completion_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'allocations','[]'::jsonb,'reservations','[]'::jsonb));
    if lot_row.allocated_weight_kg<>lot_row.total_weight_kg
      or (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations
        where ripening_lot_id=lot_value and status='active')<>lot_row.total_weight_kg then
      perform private.rpc_fail('KW400','RIPENING_WEIGHT_MISMATCH','内訳・予約合計を追熟重量と一致させてください。');
    end if;
    if exists(select 1 from public.ripening_allocations a join public.orders o on o.id=a.order_id
      where a.ripening_lot_id=lot_value and (o.status not in ('confirmed','in_progress','partially_shipped')
        or o.variety_id<>lot_row.variety_id or o.grade_id<>lot_row.grade_id)) then
      perform private.rpc_fail('KW400','ORDER_UNAVAILABLE','受注を再確認してください。');
    end if;
    if exists(select 1 from public.inventory_reservations r join public.containers c on c.id=r.container_id
      where r.ripening_lot_id=lot_value and r.status='active' and
        (c.status<>'cold_storage' or c.variety_id<>lot_row.variety_id or c.grade_id<>lot_row.grade_id)) then
      perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','予約在庫を再確認してください。');
    end if;
    update public.ripening_lots set status='confirmed',needs_review=false,version=version+1,updated_by=actor
      where id=lot_value;
  end if;
  after_value := private.ripening_audit_snapshot(lot_value,orders_value,containers_value);
  for entry in select key from jsonb_object_keys(before_value||after_value) key loop
    old_row := before_value->entry.key; new_row := after_value->entry.key;
    if old_row is not distinct from new_row then continue; end if;
    operation_value := case when old_row is null then 'create' when new_row is null then 'delete'
      when old_row->'data'->>'status' is distinct from new_row->'data'->>'status' then 'transition' else 'update' end;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
    values(coalesce(new_row,old_row)->>'entity',(coalesce(new_row,old_row)->>'id')::uuid,operation_value,
      old_row->'data',coalesce(new_row->'data',jsonb_build_object('id',old_row->>'id','deleted',true)),
      reason_value,actor,correlation);
  end loop;
  return public.ripening_plan_get(lot_value);
end;
$$;

create or replace function private.ripening_plan_rpc(function_name_value text, req jsonb)
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
      private.ripening_plan_action(function_name_value,input_value,actor_value,correlation_value));
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
  foreach function_name in array array['ripening_plan_register','ripening_plan_update','ripening_plan_confirm','ripening_plan_cancel']
  loop
    execute format($fn$
      create or replace function public.%1$I(req jsonb) returns jsonb
      language sql security definer set search_path = '' as $body$
        select private.rpc_log_response(%2$L,auth.uid(),
          private.rpc_try_uuid_v4(req->'meta'->>'correlation_id'),
          private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key'),
          private.ripening_plan_rpc(%2$L,req))
      $body$;
    $fn$,function_name,function_name);
    execute format('revoke all on function public.%I(jsonb) from public,anon',function_name);
    execute format('grant execute on function public.%I(jsonb) to authenticated,service_role',function_name);
  end loop;
end;
$$;


revoke all on function private.ripening_timestamp(jsonb,text) from public,anon,authenticated;
revoke all on function private.ripening_plan_input(jsonb) from public,anon,authenticated;
revoke all on function private.ripening_audit_snapshot(uuid,uuid[],uuid[]) from public,anon,authenticated;
revoke all on function private.ripening_plan_action(text,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function private.ripening_plan_rpc(text,jsonb) from public,anon,authenticated;
revoke all on function public.ripening_plan_get(uuid) from public,anon;
revoke all on function public.ripening_inventory_available() from public,anon;
grant execute on function public.ripening_plan_get(uuid) to authenticated,service_role;
grant execute on function public.ripening_inventory_available() to authenticated,service_role;
commit;
