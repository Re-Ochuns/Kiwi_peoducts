begin;

-- S3-08: Ripening label generation and print-state management ----------------
-- When ethylene injection completes a ripening container is created. This
-- migration:
--   1. Creates a label_job for that container inside ripening_work_action.
--   2. Guards ripening_ethylene_removal_complete until the label is handled.
--   3. Extends label_rpc to skip the sorting-specific cold_storage transition
--      for ripening containers while keeping all other label state changes.
--   4. Adds ripening_label_get for the label-pdf Edge Function to read all
--      ripening-specific fields in a single authenticated query.

-- ── 1. Replace ripening_work_action to add label_job creation and guard ───────
create or replace function private.ripening_work_action(fn text, input_value jsonb, actor uuid,
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
  label_row public.label_jobs%rowtype;
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

  -- Label guard: all ripening container labels must be handled before removal.
  if kind='ethylene_removal_check' and exists(
    select 1 from public.label_jobs j
    join public.containers c on c.id=j.container_id
    where c.ripening_lot_id=lot_id
      and j.status not in ('printed','handwritten')
  ) then
    perform private.rpc_fail('KW400','LABEL_REQUIRED',
      '追熟ラベルの印刷または手書き対応を先に完了してください。');
  end if;

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
    -- Create the ripening label job so the field team can print before removal.
    insert into public.label_jobs(container_id,created_by,updated_by)
      values(output_id,actor,actor)
      returning * into label_row;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    values('label_job',label_row.id,'create',null,to_jsonb(label_row),'追熟注入完了',actor,correlation);
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

-- ── 2. Extend label_rpc to support ripening containers ──────────────────────
-- Ripening containers stay in ethylene_processing, resting, etc. — they must
-- not be transitioned to cold_storage on label completion.  The cold_storage
-- location-type validation is also skipped for them; any active location is
-- valid as a ripening location update.
create or replace function private.label_rpc(function_name_value text, req jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  raw_correlation text;
  correlation_value uuid;
  idempotency_key_value uuid;
  input jsonb;
  actor_id uuid;
  request_hash_value text;
  claim_outcome_value text;
  stored_response_value jsonb;
  label_job_id_value uuid;
  worker_id_value uuid;
  copies_value bigint;
  notes_value text;
  reason_value text;
  location_id_value uuid;
  job public.label_jobs%rowtype;
  job_before jsonb;
  container public.containers%rowtype;
  container_before jsonb;
  is_ripening boolean;
  new_printed_copies integer;
  job_completed boolean;
  event_type_value text;
  history_reason text;
  envelope jsonb;
  error_code_value text;
  error_message_value text;
  error_details_text text;
  error_sqlstate_value text;
begin
  if req is null or jsonb_typeof(req) <> 'object' then
    return private.rpc_error_envelope(null, 'business', 'VALIDATION_FAILED',
      '要求の形式が正しくありません。', jsonb_build_object('field', 'req', 'reason', 'invalid_type'));
  end if;
  raw_correlation := req -> 'meta' ->> 'correlation_id';
  correlation_value := private.rpc_try_uuid_v4(raw_correlation);
  idempotency_key_value := private.rpc_try_uuid_v4(req -> 'meta' ->> 'idempotency_key');
  input := req -> 'input';
  if correlation_value is null then
    return private.rpc_error_envelope(raw_correlation, 'business', 'VALIDATION_FAILED',
      'correlation_id が正しくありません。',
      jsonb_build_object('field', 'meta.correlation_id', 'reason', 'invalid_format'));
  end if;
  if idempotency_key_value is null then
    return private.rpc_error_envelope(raw_correlation, 'business', 'VALIDATION_FAILED',
      'idempotency_key が正しくありません。',
      jsonb_build_object('field', 'meta.idempotency_key', 'reason', 'invalid_format'));
  end if;
  if input is null or jsonb_typeof(input) <> 'object' then
    return private.rpc_error_envelope(raw_correlation, 'business', 'VALIDATION_FAILED',
      'input が正しくありません。', jsonb_build_object('field', 'input', 'reason', 'invalid_type'));
  end if;

  actor_id := auth.uid();
  if actor_id is null then
    return private.rpc_error_envelope(raw_correlation, 'auth', 'AUTH_REQUIRED',
      'ログインが必要です。', null);
  end if;
  if not private.current_user_is_active() then
    return private.rpc_error_envelope(raw_correlation, 'auth', 'AUTH_FORBIDDEN',
      'この操作を行う権限がありません。', null);
  end if;

  request_hash_value := encode(sha256(convert_to(function_name_value || ':' || input::text, 'utf8')), 'hex');
  select claim_outcome, stored_response
  into claim_outcome_value, stored_response_value
  from private.rpc_claim_idempotency(function_name_value, idempotency_key_value, request_hash_value, actor_id);
  if claim_outcome_value = 'replay' then
    return stored_response_value
      || jsonb_build_object('correlation_id', raw_correlation, 'idempotent_replay', true);
  end if;
  if claim_outcome_value = 'reused' then
    return private.rpc_error_envelope(raw_correlation, 'conflict', 'IDEMPOTENCY_KEY_REUSED',
      '同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。', null);
  end if;

  begin
    label_job_id_value := private.rpc_input_uuid(input, 'label_job_id', true);
    worker_id_value := private.rpc_input_uuid(input, 'worker_id', true);

    if function_name_value <> 'label_reprint'
      and input ? 'reason' and jsonb_typeof(input -> 'reason') <> 'null' then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'この操作に reason は指定できません。',
        jsonb_build_object('field', 'reason', 'reason', 'not_allowed'));
    end if;
    if function_name_value = 'label_mark_handwritten'
      and input ? 'copies' and jsonb_typeof(input -> 'copies') <> 'null' then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '手書き対応に copies は指定できません。',
        jsonb_build_object('field', 'copies', 'reason', 'not_allowed'));
    end if;
    if function_name_value = 'label_reprint' then
      if input ? 'notes' and jsonb_typeof(input -> 'notes') <> 'null' then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '再印刷の理由は reason へ指定してください。',
          jsonb_build_object('field', 'notes', 'reason', 'not_allowed'));
      end if;
      if input ? 'location_id' and jsonb_typeof(input -> 'location_id') <> 'null' then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '再印刷に location_id は指定できません。',
          jsonb_build_object('field', 'location_id', 'reason', 'not_allowed'));
      end if;
      reason_value := private.rpc_input_text(input, 'reason', true);
      notes_value := reason_value;
    else
      notes_value := private.rpc_input_text(input, 'notes', false);
      location_id_value := private.rpc_input_uuid(input, 'location_id', false);
    end if;

    if function_name_value = 'label_mark_handwritten' then
      copies_value := 1;
    else
      copies_value := coalesce(private.rpc_input_positive_int(input, 'copies', false), 1);
      if copies_value > 999 then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'copies の値が範囲外です。',
          jsonb_build_object('field', 'copies', 'reason', 'out_of_range'));
      end if;
    end if;

    if not exists (select 1 from public.workers w where w.id = worker_id_value and w.is_active) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '担当者が見つからないか無効です。',
        jsonb_build_object('field', 'worker_id', 'reason', 'not_found'));
    end if;
    if location_id_value is not null then
      if not exists (
        select 1 from public.storage_locations s
        where s.id = location_id_value and s.is_active
      ) then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '保管場所が見つからないか無効です。',
          jsonb_build_object('field', 'location_id', 'reason', 'not_found'));
      end if;
    end if;

    select * into job
    from public.label_jobs
    where id = label_job_id_value
    for update;
    if not found then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '対象のラベルジョブが見つかりません。',
        jsonb_build_object('field', 'label_job_id', 'reason', 'not_found'));
    end if;

    select * into strict container
    from public.containers
    where id = job.container_id
    for update;

    -- Ripening containers stay in their work status; only sorting containers
    -- transition to cold_storage when the label job completes.
    is_ripening := container.ripening_lot_id is not null;

    -- Cold-storage type check applies only to sorting containers.
    if location_id_value is not null and not is_ripening then
      if not exists (
        select 1 from public.storage_locations s
        where s.id = location_id_value and s.location_type = 'cold_storage'
      ) then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '保管場所は冷蔵庫を指定してください。',
          jsonb_build_object('field', 'location_id', 'reason', 'invalid_value'));
      end if;
    end if;

    job_before := to_jsonb(job);

    if function_name_value in ('label_mark_printed', 'label_mark_handwritten') then
      if job.status not in ('not_printed', 'partially_printed') then
        perform private.rpc_fail('KW409', 'CONFLICT_STALE',
          'このラベルはすでに対応が完了しています。最新の状態を確認してください。',
          jsonb_build_object('current', jsonb_build_object(
            'label_job_id', job.id, 'status', job.status,
            'printed_copies', job.printed_copies, 'required_copies', job.required_copies,
            'reprint_count', job.reprint_count)));
      end if;
    end if;

    if function_name_value = 'label_mark_printed' then
      new_printed_copies := job.printed_copies + copies_value::integer;
      job_completed := new_printed_copies >= job.required_copies;
      event_type_value := 'print';
      history_reason := '印刷済み確定';
      update public.label_jobs
      set status = case when job_completed then 'printed' else 'partially_printed' end,
          printed_copies = new_printed_copies,
          completed_at = case when job_completed then now() else null end,
          completed_by = case when job_completed then worker_id_value else null end
      where id = job.id
      returning * into job;
    elsif function_name_value = 'label_mark_handwritten' then
      job_completed := true;
      event_type_value := 'handwritten';
      history_reason := '手書き対応確定';
      update public.label_jobs
      set status = 'handwritten',
          completed_at = now(),
          completed_by = worker_id_value
      where id = job.id
      returning * into job;
    else
      if job.status <> 'printed' then
        perform private.rpc_fail('KW400', 'LABEL_NOT_REPRINTABLE',
          '印刷済みのラベルだけを再印刷できます。',
          jsonb_build_object('label_job_id', job.id, 'status', job.status));
      end if;
      job_completed := false;
      event_type_value := 'reprint';
      history_reason := reason_value;
      update public.label_jobs
      set printed_copies = job.printed_copies + copies_value::integer,
          reprint_count = job.reprint_count + 1
      where id = job.id
      returning * into job;
    end if;

    insert into public.label_events (
      label_job_id, event_type, copies, performed_by, notes, created_by
    ) values (
      job.id, event_type_value, copies_value::integer, worker_id_value, notes_value, actor_id
    );

    insert into public.change_history (
      entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
    ) values (
      'label_job', job.id,
      case when function_name_value = 'label_reprint' then 'update' else 'transition' end,
      job_before, to_jsonb(job), history_reason, actor_id, correlation_value
    );

    -- Sorting containers: transition to cold_storage on completion.
    -- Ripening containers: stay in their current work status.
    if job_completed or location_id_value is not null then
      container_before := to_jsonb(container);
      update public.containers
      set status = case
            when job_completed and not is_ripening then 'cold_storage'
            else container.status end,
          location_id = coalesce(location_id_value, container.location_id),
          version = container.version + 1
      where id = container.id
      returning * into container;

      insert into public.change_history (
        entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
      ) values (
        'container', container.id,
        case when job_completed and not is_ripening then 'transition' else 'update' end,
        container_before, to_jsonb(container), history_reason, actor_id, correlation_value
      );
    end if;

    envelope := private.rpc_success_envelope(raw_correlation, jsonb_build_object(
      'label_job_id', job.id,
      'container_id', container.id,
      'status', job.status,
      'printed_copies', job.printed_copies,
      'required_copies', job.required_copies,
      'reprint_count', job.reprint_count,
      'completed_at', job.completed_at,
      'container_status', container.status,
      'container_version', container.version,
      'location_id', container.location_id
    ));
  exception
    when sqlstate 'KW400' or sqlstate 'KW409' then
      get stacked diagnostics
        error_code_value = message_text,
        error_message_value = pg_exception_hint,
        error_details_text = pg_exception_detail,
        error_sqlstate_value = returned_sqlstate;
      envelope := private.rpc_error_envelope(
        raw_correlation,
        case error_sqlstate_value when 'KW409' then 'conflict' else 'business' end,
        error_code_value,
        error_message_value,
        nullif(error_details_text, '')::jsonb
      );
  end;

  perform private.rpc_store_idempotency(idempotency_key_value, envelope);
  return envelope;
end;
$$;

-- ── 3. Read function for the label-pdf Edge Function ─────────────────────────
-- Returns all fields the ripening A5 label needs in a single authenticated
-- query. The Edge Function calls this via PostgREST RPC; RLS ensures only
-- active authenticated users can read. Returns NULL if the container_id does
-- not belong to a ripening container (caller falls back to sorting label).
create function public.ripening_label_get(container_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'container_id',   c.id,
    'display_id',     c.display_id,
    'weight_kg',      c.original_weight_kg,
    'location_name',  sl.name,
    'variety_name',   v.name,
    'grade_code',     g.code,
    'injection_at',   inj.actual_at,
    'planned_removal_at',    t_rem.scheduled_at,
    'planned_completion_at', l.planned_completion_at,
    'orchard_names',  (
      select coalesce(string_agg(distinct rec.origin_name, '・' order by rec.origin_name), '')
      from public.inventory_reservations ir
      join public.containers src on src.id = ir.container_id
      join public.sorting_results sr on sr.id = src.sorting_result_id
      join public.receiving_lots rec on rec.id = sr.receiving_lot_id
      where ir.ripening_lot_id = l.id
    ),
    'allocations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id',            a.order_id,
        'order_number',        o.order_number,
        'allocation_type',     a.allocation_type,
        'allocated_weight_kg', a.allocated_weight_kg
      ) order by a.order_id)
      from public.ripening_allocations a
      left join public.orders o on o.id = a.order_id
      where a.ripening_lot_id = l.id
    ), '[]'::jsonb)
  )
  from public.containers c
  join public.ripening_lots l    on l.id = c.ripening_lot_id
  join public.varieties v        on v.id = c.variety_id
  join public.grades g           on g.id = c.grade_id
  left join public.storage_locations sl on sl.id = c.location_id
  left join public.ripening_work_results inj
    on inj.ripening_lot_id = l.id and inj.work_type = 'ethylene_injection'
  left join public.work_tasks t_rem
    on t_rem.ripening_lot_id = l.id
   and t_rem.task_type = 'ethylene_removal_check'
   and t_rem.managed_by_planning
  where c.id = container_id_value
    and c.ripening_lot_id is not null;
$$;

revoke all on function public.ripening_label_get(uuid) from public, anon;
grant execute on function public.ripening_label_get(uuid) to authenticated, service_role;

comment on function public.ripening_label_get(uuid) is
  'Returns all fields for the ripening A5 label PDF. Returns NULL for non-ripening containers. Called by the label-pdf Edge Function (S3-08).';

commit;
