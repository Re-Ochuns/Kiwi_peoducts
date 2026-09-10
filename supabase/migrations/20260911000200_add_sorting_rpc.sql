begin;

-- sorting_confirm -------------------------------------------------------------
-- Confirms the whole-lot sorting of one receiving lot: creates the sorting
-- result, the graded containers with their initial stock and label jobs, and
-- transitions the lot to sorted, all in one transaction. Reuses the envelope,
-- idempotency, and input helpers introduced with the receiving RPCs.

create or replace function public.sorting_confirm(req jsonb)
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
  receiving_lot_id_value uuid;
  sorting_date_value date;
  worker_id_value uuid;
  expected_lot_version_value bigint;
  containers_value jsonb;
  container_elem jsonb;
  container_ordinal bigint;
  container_grade_id uuid;
  container_weight numeric;
  container_total numeric;
  sorting_display_id text;
  lot public.receiving_lots%rowtype;
  lot_before jsonb;
  sorting_row public.sorting_results%rowtype;
  container_row public.containers%rowtype;
  label_row public.label_jobs%rowtype;
  containers_data jsonb;
  envelope jsonb;
  error_code_value text;
  error_message_value text;
  error_details_text text;
  error_sqlstate_value text;
  element_details jsonb;
begin
  if req is null or jsonb_typeof(req) <> 'object' then
    return private.rpc_error_envelope(null, 'business', 'VALIDATION_FAILED',
      '要求の形式が正しくありません。', jsonb_build_object('field', 'req', 'reason', 'invalid_type'));
  end if;
  raw_correlation := req -> 'meta' ->> 'correlation_id';
  correlation_value := private.rpc_try_uuid(raw_correlation);
  idempotency_key_value := private.rpc_try_uuid(req -> 'meta' ->> 'idempotency_key');
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

  request_hash_value := encode(sha256(convert_to('sorting_confirm:' || input::text, 'utf8')), 'hex');
  select claim_outcome, stored_response
  into claim_outcome_value, stored_response_value
  from private.rpc_claim_idempotency('sorting_confirm', idempotency_key_value, request_hash_value, actor_id);
  if claim_outcome_value = 'replay' then
    return stored_response_value
      || jsonb_build_object('correlation_id', raw_correlation, 'idempotent_replay', true);
  end if;
  if claim_outcome_value = 'reused' then
    return private.rpc_error_envelope(raw_correlation, 'conflict', 'IDEMPOTENCY_KEY_REUSED',
      '同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。', null);
  end if;

  begin
    receiving_lot_id_value := private.rpc_input_uuid(input, 'receiving_lot_id', true);
    sorting_date_value := private.rpc_input_date(input, 'sorting_date', true);
    worker_id_value := private.rpc_input_uuid(input, 'worker_id', true);
    expected_lot_version_value := private.rpc_input_positive_int(input, 'expected_lot_version', true);

    containers_value := input -> 'containers';
    if containers_value is null or jsonb_typeof(containers_value) = 'null' then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果コンテナを1件以上指定してください。',
        jsonb_build_object('field', 'containers', 'reason', 'required'));
    elsif jsonb_typeof(containers_value) <> 'array' then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果コンテナは配列で指定してください。',
        jsonb_build_object('field', 'containers', 'reason', 'invalid_type'));
    elsif jsonb_array_length(containers_value) = 0 then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果コンテナを1件以上指定してください。',
        jsonb_build_object('field', 'containers', 'reason', 'required'));
    end if;

    if not exists (select 1 from public.workers w where w.id = worker_id_value and w.is_active) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '担当者が見つからないか無効です。',
        jsonb_build_object('field', 'worker_id', 'reason', 'not_found'));
    end if;

    container_total := 0;
    for container_elem, container_ordinal in
      select value, ordinality from jsonb_array_elements(containers_value) with ordinality
    loop
      if jsonb_typeof(container_elem) <> 'object' then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果コンテナの形式が正しくありません。',
          jsonb_build_object('field', format('containers[%s]', container_ordinal - 1), 'reason', 'invalid_type'));
      end if;
      begin
        container_grade_id := private.rpc_input_uuid(container_elem, 'grade_id', true);
        container_weight := private.rpc_input_weight(container_elem, 'weight_kg', true, false);
      exception
        when sqlstate 'KW400' then
          get stacked diagnostics
            error_code_value = message_text,
            error_message_value = pg_exception_hint,
            error_details_text = pg_exception_detail;
          element_details := coalesce(nullif(error_details_text, '')::jsonb, '{}'::jsonb);
          element_details := jsonb_set(element_details, '{field}',
            to_jsonb(format('containers[%s].%s', container_ordinal - 1, coalesce(element_details ->> 'field', ''))));
          perform private.rpc_fail('KW400', error_code_value, error_message_value, element_details);
      end;
      if not exists (select 1 from public.grades g where g.id = container_grade_id and g.is_active) then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '等級が見つからないか無効です。',
          jsonb_build_object('field', format('containers[%s].grade_id', container_ordinal - 1), 'reason', 'not_found'));
      end if;
      container_total := container_total + container_weight;
    end loop;

    select * into lot
    from public.receiving_lots
    where id = receiving_lot_id_value
    for update;
    if not found then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '対象の受入ロットが見つかりません。',
        jsonb_build_object('field', 'receiving_lot_id', 'reason', 'not_found'));
    end if;
    if lot.status <> 'awaiting_sorting' then
      perform private.rpc_fail('KW409', 'CONFLICT_STALE',
        'このロットはすでに選果が確定されています。最新の状態を確認してください。',
        jsonb_build_object('current', jsonb_build_object(
          'receiving_lot_id', lot.id, 'status', lot.status, 'version', lot.version,
          'total_weight_kg', lot.total_weight_kg)));
    end if;
    if lot.version <> expected_lot_version_value then
      perform private.rpc_fail('KW409', 'CONFLICT_STALE',
        'この受入ロットは他の操作で更新されています。最新の状態を確認してください。',
        jsonb_build_object('current', jsonb_build_object(
          'receiving_lot_id', lot.id, 'status', lot.status, 'version', lot.version,
          'total_weight_kg', lot.total_weight_kg)));
    end if;
    if container_total > lot.total_weight_kg then
      perform private.rpc_fail('KW400', 'SORTING_WEIGHT_EXCEEDED',
        '選果後の合計重量が受入重量を超えています。',
        jsonb_build_object('input_total_kg', container_total, 'lot_total_kg', lot.total_weight_kg));
    end if;

    sorting_display_id := private.next_display_id('選果', extract(year from sorting_date_value)::integer);

    insert into public.sorting_results (
      display_id, receiving_lot_id, sorted_on, sorted_by,
      input_weight_kg, output_weight_kg, loss_weight_kg, created_by, updated_by
    ) values (
      sorting_display_id, lot.id, sorting_date_value, worker_id_value,
      lot.total_weight_kg, container_total, lot.total_weight_kg - container_total,
      actor_id, actor_id
    )
    returning * into sorting_row;

    containers_data := '[]'::jsonb;
    for container_elem, container_ordinal in
      select value, ordinality from jsonb_array_elements(containers_value) with ordinality
    loop
      insert into public.containers (
        display_id, sorting_result_id, variety_id, grade_id,
        original_weight_kg, current_weight_kg, created_by, updated_by
      ) values (
        sorting_display_id || '-' || container_ordinal::text,
        sorting_row.id,
        lot.variety_id,
        (container_elem ->> 'grade_id')::uuid,
        (container_elem ->> 'weight_kg')::public.weight_kg,
        (container_elem ->> 'weight_kg')::public.weight_kg,
        actor_id, actor_id
      )
      returning * into container_row;

      insert into public.label_jobs (container_id, created_by, updated_by)
      values (container_row.id, actor_id, actor_id)
      returning * into label_row;

      insert into public.change_history (
        entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
      ) values
        ('container', container_row.id, 'create', null, to_jsonb(container_row), '選果確定', actor_id, correlation_value),
        ('label_job', label_row.id, 'create', null, to_jsonb(label_row), '選果確定', actor_id, correlation_value);

      containers_data := containers_data || jsonb_build_array(jsonb_build_object(
        'container_id', container_row.id,
        'display_id', container_row.display_id,
        'grade_id', container_row.grade_id,
        'weight_kg', container_row.original_weight_kg,
        'status', container_row.status));
    end loop;

    lot_before := to_jsonb(lot);
    update public.receiving_lots
    set status = 'sorted', version = lot.version + 1
    where id = lot.id
    returning * into lot;

    insert into public.change_history (
      entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
    ) values
      ('sorting_result', sorting_row.id, 'create', null, to_jsonb(sorting_row), '選果確定', actor_id, correlation_value),
      ('receiving_lot', lot.id, 'transition', lot_before, to_jsonb(lot), '選果確定', actor_id, correlation_value);

    envelope := private.rpc_success_envelope(raw_correlation, jsonb_build_object(
      'sorting_result_id', sorting_row.id,
      'display_id', sorting_row.display_id,
      'sorting_date', to_char(sorting_row.sorted_on, 'YYYY-MM-DD'),
      'input_weight_kg', sorting_row.input_weight_kg,
      'output_weight_kg', sorting_row.output_weight_kg,
      'loss_weight_kg', sorting_row.loss_weight_kg,
      'receiving_lot_id', lot.id,
      'receiving_lot_status', lot.status,
      'receiving_lot_version', lot.version,
      'containers', containers_data
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

revoke all on function public.sorting_confirm(jsonb) from public, anon;
grant execute on function public.sorting_confirm(jsonb) to authenticated, service_role;

comment on function public.sorting_confirm(jsonb) is
  'Confirms whole-lot sorting: creates the sorting result, graded containers with initial stock and label jobs, and closes the receiving lot atomically.';

commit;
