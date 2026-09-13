begin;

create function private.ripening_work_temperature(input_value jsonb, field_name text)
returns numeric language plpgsql set search_path = '' as $$
declare value numeric;
begin
  if jsonb_typeof(input_value->field_name) is distinct from 'number' then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','温度を数値で指定してください。',
      jsonb_build_object('field',field_name,'reason','invalid_type'));
  end if;
  value := (input_value->>field_name)::numeric;
  if value <= '-Infinity'::numeric or value >= 'Infinity'::numeric then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','有限の温度を指定してください。');
  end if;
  return value;
end;
$$;

create function public.ripening_work_get(ripening_lot_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select public.ripening_plan_get(l.id) || jsonb_build_object(
    'results', coalesce((select jsonb_agg(to_jsonb(r) order by r.actual_at,r.id)
      from public.ripening_work_results r where r.ripening_lot_id=l.id),'[]'::jsonb),
    'containers', coalesce((select jsonb_agg(to_jsonb(c) order by c.display_id)
      from public.containers c where c.ripening_lot_id=l.id),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(to_jsonb(t) order by t.task_type)
      from public.work_tasks t where t.ripening_lot_id=l.id),'[]'::jsonb))
  from public.ripening_lots l where l.id=ripening_lot_id_value;
$$;

create function private.ripening_work_action(fn text, input_value jsonb, actor uuid,
  correlation uuid, operation uuid)
returns jsonb language plpgsql set search_path = '' as $$
declare
  kind text;
  lot_id uuid;
  expected bigint;
  location_value uuid;
  worker_value uuid;
  actual_value timestamptz;
  temperature_value numeric;
  resting_value timestamptz;
  rest_temperature_value numeric;
  notes_value text;
  lot public.ripening_lots%rowtype;
  source public.containers%rowtype;
  reservation public.inventory_reservations%rowtype;
  target public.containers%rowtype;
  task public.work_tasks%rowtype;
  downstream_task public.work_tasks%rowtype;
  location_name text;
  previous_result public.ripening_work_results%rowtype;
  order_ids uuid[];
  source_ids uuid[];
  before_value jsonb;
  after_value jsonb;
  old_row jsonb;
  new_row jsonb;
  entry record;
  task_before jsonb;
  output_id uuid;
begin
  kind := case fn
    when 'ripening_ethylene_injection_complete' then 'ethylene_injection'
    when 'ripening_ethylene_removal_complete' then 'ethylene_removal_check'
    when 'ripening_ripeness_complete' then 'ripeness_check'
    else null end;
  if kind is null then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','未対応の作業です。');
  end if;
  perform private.customer_order_validate_keys(input_value,
    array['ripening_lot_id','expected_version','actual_at','actual_temperature',
      'location_id','performed_by','checked','notes'] ||
    case when kind='ethylene_removal_check' then array['rest_started_at','rest_temperature']
      else array[]::text[] end);
  lot_id := private.rpc_input_uuid(input_value,'ripening_lot_id',true);
  expected := private.rpc_input_positive_int(input_value,'expected_version',true);
  location_value := private.rpc_input_uuid(input_value,'location_id',true);
  worker_value := private.rpc_input_uuid(input_value,'performed_by',true);
  notes_value := private.rpc_input_text(input_value,'notes',false);
  if input_value->'checked' is distinct from 'true'::jsonb then
    perform private.rpc_fail('KW400','CONFIRMATION_REQUIRED','対象と作業の実施確認が必要です。');
  end if;
  actual_value := case when not (input_value ? 'actual_at') then statement_timestamp()
    else private.ripening_timestamp(input_value,'actual_at') end;
  temperature_value := private.ripening_work_temperature(input_value,'actual_temperature');
  if kind='ethylene_removal_check' then
    resting_value := case when not (input_value ? 'rest_started_at') then actual_value
      else private.ripening_timestamp(input_value,'rest_started_at') end;
    rest_temperature_value := private.ripening_work_temperature(input_value,'rest_temperature');
    if resting_value < actual_value then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','寝かせ開始は抜き確認以降にしてください。');
    end if;
  end if;
  -- Same lock as S2 planning/order mutations: preserve confirmed allocations.
  perform pg_advisory_xact_lock(53,0);
  select * into lot from public.ripening_lots where id=lot_id for update;
  if not found then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟計画が見つかりません。');
  end if;
  if lot.version<>expected then
    perform private.rpc_fail('KW409','CONFLICT_STALE','最新の追熟計画を読み直してください。',
      jsonb_build_object('current_version',lot.version));
  end if;
  if (kind='ethylene_injection' and lot.status<>'confirmed')
    or (kind<>'ethylene_injection' and lot.status<>'in_progress')
    or exists(select 1 from public.ripening_work_results r
      where r.ripening_lot_id=lot_id and r.work_type=kind) then
    perform private.rpc_fail('KW409','INVALID_WORK_STATE','この工程は実行できないか完了済みです。');
  end if;
  if not exists(select 1 from public.workers where id=worker_value and is_active for share)
    or not exists(select 1 from public.storage_locations where id=location_value and is_active for share) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','担当者または場所が無効です。');
  end if;
  select * into task from public.work_tasks
    where ripening_lot_id=lot_id and task_type=kind and managed_by_planning for update;
  if not found or task.status<>'pending' then
    perform private.rpc_fail('KW409','INVALID_WORK_STATE','対象作業が見つからないか完了済みです。');
  end if;
  task_before := to_jsonb(task);
  select coalesce(array_agg(distinct order_id order by order_id),array[]::uuid[]) into order_ids
    from public.ripening_allocations where ripening_lot_id=lot_id and order_id is not null;
  select coalesce(array_agg(container_id order by container_id),array[]::uuid[]) into source_ids
    from public.inventory_reservations where ripening_lot_id=lot_id;
  perform 1 from public.orders where id=any(order_ids) order by id for update;
  perform 1 from public.containers where id=any(source_ids) or ripening_lot_id=lot_id
    order by id for update;
  before_value := private.ripening_audit_snapshot(lot_id,order_ids,array[]::uuid[]);
  if kind='ethylene_injection' then
    if lot.needs_review or lot.allocated_weight_kg<>lot.total_weight_kg
      or (select coalesce(sum(allocated_weight_kg),0) from public.ripening_allocations
        where ripening_lot_id=lot_id)<>lot.total_weight_kg
      or (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations
        where ripening_lot_id=lot_id and status='active')<>lot.total_weight_kg then
      perform private.rpc_fail('KW400','RIPENING_WEIGHT_MISMATCH','内訳と予約を再確認してください。');
    end if;
    if exists(select 1 from public.orders o where o.id=any(order_ids)
      and (o.status not in ('confirmed','in_progress','partially_shipped')
        or o.variety_id<>lot.variety_id or o.grade_id<>lot.grade_id)) then
      perform private.rpc_fail('KW400','ORDER_UNAVAILABLE','割当受注を再確認してください。');
    end if;
    if exists(select 1 from public.containers where ripening_lot_id=lot_id) then
      perform private.rpc_fail('KW409','INVALID_WORK_STATE','追熟コンテナは作成済みです。');
    end if;
    for reservation in select * from public.inventory_reservations
      where ripening_lot_id=lot_id and status='active' order by container_id
    loop
      select * into source from public.containers where id=reservation.container_id;
      if source.status<>'cold_storage' or source.variety_id<>lot.variety_id
        or source.grade_id<>lot.grade_id or source.current_weight_kg<source.reserved_weight_kg then
        perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','予約元在庫を再確認してください。');
      end if;
      update public.inventory_reservations set status='consumed',consumed_at=actual_value,updated_by=actor
        where id=reservation.id;
      insert into public.inventory_events (
        container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
        ripening_lot_id,operation_id,occurred_at,reason,created_by
      ) values(source.id,'ripening_out',-reservation.reserved_weight_kg,source.current_weight_kg,
        source.current_weight_kg-reservation.reserved_weight_kg,lot_id,operation,actual_value,'追熟注入開始',actor);
    end loop;
    output_id := gen_random_uuid();
    insert into public.containers (
      id,display_id,ripening_lot_id,variety_id,grade_id,original_weight_kg,current_weight_kg,
      status,location_id,created_by,updated_by
    ) values(output_id,lot.display_id||'-1',lot_id,lot.variety_id,lot.grade_id,
      lot.total_weight_kg,0,'ethylene_processing',location_value,actor,actor);
    insert into public.inventory_events (
      container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
      ripening_lot_id,operation_id,occurred_at,reason,created_by
    ) values(output_id,'ripening_in',lot.total_weight_kg,0,lot.total_weight_kg,
      lot_id,operation,actual_value,'追熟コンテナ生成',actor);
    update public.orders set status='in_progress',version=version+1,updated_by=actor
      where id=any(order_ids) and status='confirmed';
    update public.ripening_lots set status='in_progress',version=version+1,updated_by=actor
      where id=lot_id;
  else
    select * into previous_result from public.ripening_work_results r
      where r.ripening_lot_id=lot_id and r.work_type=
        case when kind='ethylene_removal_check' then 'ethylene_injection' else 'ethylene_removal_check' end;
    if not found then
      perform private.rpc_fail('KW409','INVALID_WORK_STATE','前工程を完了してください。');
    end if;
    if actual_value < coalesce(previous_result.rest_started_at,previous_result.actual_at) then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','実績日時は前工程以降を指定してください。');
    end if;
    if not exists(select 1 from public.containers where ripening_lot_id=lot_id)
      or exists(select 1 from public.containers where ripening_lot_id=lot_id and
        ((kind='ethylene_removal_check' and status<>'ethylene_processing') or
         (kind='ripeness_check' and status not in ('resting','awaiting_ripeness_check')))) then
      perform private.rpc_fail('KW409','INVALID_WORK_STATE','現物工程を再確認してください。');
    end if;
    for target in select * from public.containers where ripening_lot_id=lot_id order by id loop
      if kind='ripeness_check' and target.status='resting' then
        update public.containers set status='awaiting_ripeness_check' where id=target.id;
      end if;
      update public.containers set status=case when kind='ethylene_removal_check'
          then 'resting' else 'shippable' end,
        location_id=location_value,version=version+1,updated_by=actor where id=target.id;
      insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
        reason,changed_by,correlation_id)
      select 'container',target.id,'transition',to_jsonb(target),to_jsonb(c),kind,actor,correlation
        from public.containers c where id=target.id;
    end loop;
    update public.ripening_lots set status=case when kind='ripeness_check' then 'completed' else status end,
      version=version+1,updated_by=actor where id=lot_id;
  end if;
  insert into public.ripening_work_results (
    ripening_lot_id,work_type,actual_at,actual_temperature,location_id,performed_by,
    checked,rest_started_at,rest_temperature,notes,operation_id,created_by
  ) values(lot_id,kind,actual_value,temperature_value,location_value,worker_value,
    true,resting_value,rest_temperature_value,notes_value,operation,actor);
  update public.work_tasks set status='completed',completed_at=actual_value,completed_by=worker_value,
    notes=notes_value,version=version+1,updated_by=actor where id=task.id;
  insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
    reason,changed_by,correlation_id)
  select 'work_task',task.id,'transition',task_before,to_jsonb(t),kind,actor,correlation
    from public.work_tasks t where id=task.id;
  -- Actual placement is the next worker's destination, without replanning dates.
  select name into location_name from public.storage_locations where id=location_value;
  for downstream_task in
    select * from public.work_tasks
    where ripening_lot_id=lot_id and managed_by_planning and status='pending'
      and ((kind='ethylene_injection' and task_type in ('ethylene_removal_check','ripeness_check'))
        or (kind='ethylene_removal_check' and task_type='ripeness_check'))
      and task_details->>'location' is distinct from location_name
    order by id for update
  loop
    update public.work_tasks
      set task_details=jsonb_set(task_details,'{location}',to_jsonb(location_name),true),
        version=version+1,updated_by=actor
      where id=downstream_task.id;
    -- Updating task_details also queues the new calendar revision.
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    select 'work_task',t.id,'update',to_jsonb(downstream_task),to_jsonb(t),
      kind,actor,correlation from public.work_tasks t where t.id=downstream_task.id;
  end loop;
  after_value := private.ripening_audit_snapshot(lot_id,order_ids,array[]::uuid[]);
  for entry in select key from jsonb_object_keys(before_value||after_value) key loop
    old_row := before_value->entry.key; new_row := after_value->entry.key;
    if old_row is not distinct from new_row then continue; end if;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    values(new_row->>'entity',(new_row->>'id')::uuid,'update',old_row->'data',new_row->'data',kind,actor,correlation);
  end loop;
  return public.ripening_work_get(lot_id);
end;
$$;
create or replace function private.ripening_work_rpc(function_name_value text, req jsonb)
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
      private.ripening_work_action(function_name_value,input_value,actor_value,correlation_value,key_value));
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
  foreach function_name in array array['ripening_ethylene_injection_complete','ripening_ethylene_removal_complete','ripening_ripeness_complete']
  loop
    execute format($fn$
      create or replace function public.%1$I(req jsonb) returns jsonb
      language sql security definer set search_path = '' as $body$
        select private.rpc_log_response(%2$L,auth.uid(),
          private.rpc_try_uuid_v4(req->'meta'->>'correlation_id'),
          private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key'),
          private.ripening_work_rpc(%2$L,req))
      $body$;
    $fn$,function_name,function_name);
    execute format('revoke all on function public.%I(jsonb) from public,anon',function_name);
    execute format('grant execute on function public.%I(jsonb) to authenticated,service_role',function_name);
  end loop;
end;
$$;


revoke all on function private.ripening_work_temperature(jsonb,text),
  private.ripening_work_action(text,jsonb,uuid,uuid,uuid),
  private.ripening_work_rpc(text,jsonb) from public,anon,authenticated;
revoke all on function public.ripening_work_get(uuid) from public,anon;
grant execute on function public.ripening_work_get(uuid) to authenticated,service_role;
commit;
