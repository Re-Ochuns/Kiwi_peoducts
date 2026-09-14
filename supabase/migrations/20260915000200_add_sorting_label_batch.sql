begin;

-- Returns every original container label for one sorting result in the stable
-- business order used by the combined A5 PDF.
create function public.sorting_labels_get(sorting_result_id_value uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'sorting_result_id', sr.id,
    'display_id', sr.display_id,
    'containers', jsonb_agg(
      jsonb_build_object(
        'container_id', c.id,
        'display_id', c.display_id,
        'weight_kg', c.original_weight_kg,
        'grade_code', g.code,
        'variety_name', v.name,
        'origin_name', receiving.origin_name,
        'sorted_on', to_char(sr.sorted_on, 'YYYY-MM-DD'),
        'worker_name', worker.display_name
      ) order by g.display_order, c.display_id
    )
  )
  from public.sorting_results sr
  join public.receiving_lots receiving on receiving.id = sr.receiving_lot_id
  join public.workers worker on worker.id = sr.sorted_by
  join public.containers c on c.sorting_result_id = sr.id
    and c.ripening_lot_id is null
  join public.grades g on g.id = c.grade_id
  join public.varieties v on v.id = c.variety_id
  where sr.id = sorting_result_id_value
  group by sr.id, sr.display_id;
$$;

revoke all on function public.sorting_labels_get(uuid) from public, anon;
grant execute on function public.sorting_labels_get(uuid) to authenticated, service_role;

-- Records every pending label from one sorting result as printed in one
-- transaction. A failed call cannot leave only part of the batch completed.
create function public.label_batch_mark_printed(req jsonb)
returns jsonb
language plpgsql
security definer
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
  sorting_result_id_value uuid;
  worker_id_value uuid;
  location_id_value uuid;
  target record;
  job public.label_jobs%rowtype;
  container public.containers%rowtype;
  job_before jsonb;
  container_before jsonb;
  remaining_copies integer;
  container_count integer;
  target_count integer;
  completed_data jsonb := '[]'::jsonb;
  envelope jsonb;
  error_code_value text;
  error_message_value text;
  error_details_text text;
  error_sqlstate_value text;
begin
  if req is null or jsonb_typeof(req) <> 'object' then
    return private.rpc_error_envelope(null, 'business', 'VALIDATION_FAILED',
      '要求の形式が正しくありません。',
      jsonb_build_object('field', 'req', 'reason', 'invalid_type'));
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
      'input が正しくありません。',
      jsonb_build_object('field', 'input', 'reason', 'invalid_type'));
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

  request_hash_value := encode(
    sha256(convert_to('label_batch_mark_printed:' || input::text, 'utf8')),
    'hex'
  );
  select claim_outcome, stored_response
  into claim_outcome_value, stored_response_value
  from private.rpc_claim_idempotency(
    'label_batch_mark_printed', idempotency_key_value, request_hash_value, actor_id
  );
  if claim_outcome_value = 'replay' then
    return stored_response_value || jsonb_build_object(
      'correlation_id', raw_correlation,
      'idempotent_replay', true
    );
  end if;
  if claim_outcome_value = 'reused' then
    return private.rpc_error_envelope(raw_correlation, 'conflict',
      'IDEMPOTENCY_KEY_REUSED',
      '同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。',
      null);
  end if;

  begin
    sorting_result_id_value := private.rpc_input_uuid(input, 'sorting_result_id', true);
    worker_id_value := private.rpc_input_uuid(input, 'worker_id', true);
    location_id_value := private.rpc_input_uuid(input, 'location_id', false);

    if not exists (
      select 1 from public.sorting_results where id = sorting_result_id_value
    ) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        '対象の選果結果が見つかりません。',
        jsonb_build_object('field', 'sorting_result_id', 'reason', 'not_found'));
    end if;
    if not exists (
      select 1 from public.workers where id = worker_id_value and is_active
    ) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        '担当者が見つからないか無効です。',
        jsonb_build_object('field', 'worker_id', 'reason', 'not_found'));
    end if;
    if location_id_value is not null and not exists (
      select 1 from public.storage_locations
      where id = location_id_value and is_active and location_type = 'cold_storage'
    ) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        '保管場所は有効な冷蔵庫を指定してください。',
        jsonb_build_object('field', 'location_id', 'reason', 'not_found'));
    end if;

    select count(*) into container_count
    from public.containers c
    where c.sorting_result_id = sorting_result_id_value
      and c.ripening_lot_id is null;
    if container_count = 0 then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        '対象のラベルが見つかりません。',
        jsonb_build_object('field', 'sorting_result_id', 'reason', 'no_labels'));
    end if;

    select count(*) into target_count
    from public.label_jobs lj
    join public.containers c on c.id = lj.container_id
    where c.sorting_result_id = sorting_result_id_value
      and c.ripening_lot_id is null;
    if target_count <> container_count then
      perform private.rpc_fail('KW409', 'CONFLICT_STALE',
        'コンテナ数とラベル数が一致しません。最新の状態を確認してください。',
        jsonb_build_object('current', jsonb_build_object(
          'container_count', container_count,
          'label_count', target_count
        )));
    end if;

    for target in
      select lj.id as label_job_id, c.id as container_id
      from public.label_jobs lj
      join public.containers c on c.id = lj.container_id
      join public.grades g on g.id = c.grade_id
      where c.sorting_result_id = sorting_result_id_value
        and c.ripening_lot_id is null
      order by g.display_order, c.display_id
    loop
      select * into job from public.label_jobs
      where id = target.label_job_id for update;
      select * into container from public.containers
      where id = target.container_id for update;

      if job.status not in ('not_printed', 'partially_printed') then
        perform private.rpc_fail('KW409', 'CONFLICT_STALE',
          '一括印刷の対象に対応済みラベルがあります。最新の状態を確認してください。',
          jsonb_build_object('current', jsonb_build_object(
            'label_job_id', job.id,
            'status', job.status,
            'printed_copies', job.printed_copies,
            'required_copies', job.required_copies
          )));
      end if;
      if container.status <> 'awaiting_label' then
        perform private.rpc_fail('KW409', 'CONFLICT_STALE',
          '一括印刷の対象に次工程へ進んだコンテナがあります。最新の状態を確認してください。',
          jsonb_build_object('current', jsonb_build_object(
            'container_id', container.id,
            'status', container.status,
            'version', container.version
          )));
      end if;

      remaining_copies := job.required_copies - job.printed_copies;
      job_before := to_jsonb(job);
      update public.label_jobs
      set status = 'printed',
          printed_copies = required_copies,
          completed_at = now(),
          completed_by = worker_id_value
      where id = job.id
      returning * into job;

      insert into public.label_events (
        label_job_id, event_type, copies, performed_by, created_by
      ) values (
        job.id, 'print', remaining_copies, worker_id_value, actor_id
      );
      insert into public.change_history (
        entity_type, entity_id, operation, before_data, after_data,
        reason, changed_by, correlation_id
      ) values (
        'label_job', job.id, 'transition', job_before, to_jsonb(job),
        '一括印刷済み確定', actor_id, correlation_value
      );

      container_before := to_jsonb(container);
      update public.containers
      set status = 'cold_storage',
          location_id = coalesce(location_id_value, container.location_id),
          version = version + 1
      where id = container.id
      returning * into container;
      insert into public.change_history (
        entity_type, entity_id, operation, before_data, after_data,
        reason, changed_by, correlation_id
      ) values (
        'container', container.id, 'transition', container_before,
        to_jsonb(container), '一括印刷済み確定', actor_id, correlation_value
      );

      completed_data := completed_data || jsonb_build_array(jsonb_build_object(
        'label_job_id', job.id,
        'container_id', container.id,
        'status', job.status,
        'printed_copies', job.printed_copies,
        'required_copies', job.required_copies,
        'container_status', container.status,
        'container_version', container.version
      ));
    end loop;

    envelope := private.rpc_success_envelope(raw_correlation, jsonb_build_object(
      'sorting_result_id', sorting_result_id_value,
      'completed_count', target_count,
      'labels', completed_data
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

revoke all on function public.label_batch_mark_printed(jsonb) from public, anon;
grant execute on function public.label_batch_mark_printed(jsonb) to authenticated, service_role;

comment on function public.sorting_labels_get(uuid) is
  'Returns original sorting labels in grade and container display order for one combined A5 PDF.';
comment on function public.label_batch_mark_printed(jsonb) is
  'Atomically records all original container labels from one sorting result as printed.';

commit;
