begin;

-- Label print-state RPCs -------------------------------------------------------
-- label_mark_printed, label_mark_handwritten, and label_reprint share one
-- implementation in private.label_rpc. Each operation appends a label event,
-- mirrors the change to the audit history, and, when the label job completes,
-- moves the container into cold storage in the same transaction. PDF
-- generation is a stateless Edge Function and never mutates these tables.

create or replace function private.label_rpc(function_name_value text, req jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
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
      if not exists (
        select 1 from public.storage_locations s
        where s.id = location_id_value and s.location_type = 'cold_storage'
      ) then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '保管場所は冷蔵庫を指定してください。',
          jsonb_build_object('field', 'location_id', 'reason', 'invalid_value'));
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

    if job_completed or location_id_value is not null then
      container_before := to_jsonb(container);
      update public.containers
      set status = case when job_completed then 'cold_storage' else container.status end,
          location_id = coalesce(location_id_value, container.location_id),
          version = container.version + 1
      where id = container.id
      returning * into container;

      insert into public.change_history (
        entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
      ) values (
        'container', container.id,
        case when job_completed then 'transition' else 'update' end,
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

create or replace function public.label_mark_printed(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.label_rpc('label_mark_printed', req);
$$;

create or replace function public.label_mark_handwritten(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.label_rpc('label_mark_handwritten', req);
$$;

create or replace function public.label_reprint(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.label_rpc('label_reprint', req);
$$;

revoke all on function private.label_rpc(text, jsonb) from public, anon, authenticated;
revoke all on function public.label_mark_printed(jsonb) from public, anon;
revoke all on function public.label_mark_handwritten(jsonb) from public, anon;
revoke all on function public.label_reprint(jsonb) from public, anon;
grant execute on function public.label_mark_printed(jsonb) to authenticated, service_role;
grant execute on function public.label_mark_handwritten(jsonb) to authenticated, service_role;
grant execute on function public.label_reprint(jsonb) to authenticated, service_role;

comment on function public.label_mark_printed(jsonb) is
  'Records printed label copies, completes the label job when required copies are reached, and moves the container to cold storage on completion.';
comment on function public.label_mark_handwritten(jsonb) is
  'Completes a label job as handwritten and moves the container to cold storage.';
comment on function public.label_reprint(jsonb) is
  'Records a reprint of a completed printed label with a mandatory reason.';

commit;
