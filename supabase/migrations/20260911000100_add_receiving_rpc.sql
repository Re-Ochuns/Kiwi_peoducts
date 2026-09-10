begin;

-- Display ID sequences ------------------------------------------------------
-- Issued numbers are per prefix and per year. Rows are created on demand and
-- the upsert row lock serializes concurrent number issuance.

create table private.display_id_counters (
  id_prefix text not null check (btrim(id_prefix) <> ''),
  year_number integer not null check (year_number between 2000 and 9999),
  last_number integer not null check (last_number > 0),
  primary key (id_prefix, year_number)
);

revoke all on private.display_id_counters from public, anon, authenticated;
grant all on private.display_id_counters to service_role;

create or replace function private.next_display_id(prefix_value text, year_value integer)
returns text
language plpgsql
set search_path = ''
as $$
declare
  next_number integer;
begin
  insert into private.display_id_counters as c (id_prefix, year_number, last_number)
  values (prefix_value, year_value, 1)
  on conflict (id_prefix, year_number)
  do update set last_number = c.last_number + 1
  returning last_number into next_number;
  return prefix_value || '-' || year_value::text || '-'
    || lpad(next_number::text, greatest(3, length(next_number::text)), '0');
end;
$$;

-- RPC envelope helpers -------------------------------------------------------
-- Business rule failures raise SQLSTATE KW400 and conflicts raise KW409.
-- RPC entry points catch only these two states and convert them into the
-- common envelope; every other exception rolls back the whole transaction.

create or replace function private.rpc_fail(
  fail_sqlstate text,
  fail_code text,
  fail_message text,
  fail_details jsonb default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = fail_sqlstate,
    message = fail_code,
    hint = fail_message,
    detail = coalesce(fail_details::text, '');
end;
$$;

create or replace function private.rpc_try_uuid(value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return value::uuid;
exception
  when others then
    return null;
end;
$$;

-- Envelope keys (idempotency_key, correlation_id) must be UUID v4 per the
-- common contract. Business entity references (variety_id, grade_id, …) keep
-- using rpc_try_uuid because master data uses deterministic non-v4 ids.
create or replace function private.rpc_try_uuid_v4(value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  parsed uuid;
begin
  parsed := value::uuid;
  if parsed::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return parsed;
  end if;
  return null;
exception
  when others then
    return null;
end;
$$;

create or replace function private.rpc_input_text(input jsonb, field_name text, is_required boolean)
returns text
language plpgsql
set search_path = ''
as $$
declare
  raw jsonb;
  text_value text;
begin
  raw := input -> field_name;
  if raw is null or jsonb_typeof(raw) = 'null' then
    if is_required then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        format('%s は必須です。', field_name),
        jsonb_build_object('field', field_name, 'reason', 'required'));
    end if;
    return null;
  end if;
  if jsonb_typeof(raw) <> 'string' then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s の形式が正しくありません。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'invalid_type'));
  end if;
  text_value := btrim(input ->> field_name);
  if text_value = '' then
    if is_required then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        format('%s は必須です。', field_name),
        jsonb_build_object('field', field_name, 'reason', 'required'));
    end if;
    return null;
  end if;
  return text_value;
end;
$$;

create or replace function private.rpc_input_uuid(input jsonb, field_name text, is_required boolean)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  text_value text;
  uuid_value uuid;
begin
  text_value := private.rpc_input_text(input, field_name, is_required);
  if text_value is null then
    return null;
  end if;
  uuid_value := private.rpc_try_uuid(text_value);
  if uuid_value is null then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s の形式が正しくありません。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'invalid_format'));
  end if;
  return uuid_value;
end;
$$;

create or replace function private.rpc_input_date(input jsonb, field_name text, is_required boolean)
returns date
language plpgsql
set search_path = ''
as $$
declare
  text_value text;
  date_value date;
begin
  text_value := private.rpc_input_text(input, field_name, is_required);
  if text_value is null then
    return null;
  end if;
  if text_value !~ '^\d{4}-\d{2}-\d{2}$' then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s はYYYY-MM-DD形式で指定してください。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'invalid_format'));
  end if;
  begin
    date_value := text_value::date;
  exception
    when others then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        format('%s は実在する日付を指定してください。', field_name),
        jsonb_build_object('field', field_name, 'reason', 'invalid_format'));
  end;
  return date_value;
end;
$$;

create or replace function private.rpc_input_weight(input jsonb, field_name text, is_required boolean, allow_zero boolean)
returns numeric
language plpgsql
set search_path = ''
as $$
declare
  raw jsonb;
  numeric_value numeric;
begin
  raw := input -> field_name;
  if raw is null or jsonb_typeof(raw) = 'null' then
    if is_required then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        format('%s は必須です。', field_name),
        jsonb_build_object('field', field_name, 'reason', 'required'));
    end if;
    return null;
  end if;
  if jsonb_typeof(raw) <> 'number' then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s は数値で指定してください。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'invalid_type'));
  end if;
  numeric_value := (input ->> field_name)::numeric;
  if numeric_value <> round(numeric_value, 2) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s は0.01kg単位で指定してください。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'invalid_precision'));
  end if;
  if numeric_value < 0
    or (numeric_value = 0 and not allow_zero)
    or numeric_value > 9999999999.99 then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s の値が範囲外です。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'out_of_range'));
  end if;
  return numeric_value;
end;
$$;

create or replace function private.rpc_input_positive_int(input jsonb, field_name text, is_required boolean)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  raw jsonb;
  numeric_value numeric;
begin
  raw := input -> field_name;
  if raw is null or jsonb_typeof(raw) = 'null' then
    if is_required then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        format('%s は必須です。', field_name),
        jsonb_build_object('field', field_name, 'reason', 'required'));
    end if;
    return null;
  end if;
  if jsonb_typeof(raw) <> 'number' then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s は数値で指定してください。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'invalid_type'));
  end if;
  numeric_value := (input ->> field_name)::numeric;
  if numeric_value <> trunc(numeric_value)
    or numeric_value < 1
    or numeric_value > 9223372036854775807 then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      format('%s は1以上の整数で指定してください。', field_name),
      jsonb_build_object('field', field_name, 'reason', 'out_of_range'));
  end if;
  return numeric_value::bigint;
end;
$$;

create or replace function private.rpc_success_envelope(correlation_value text, data_value jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'ok', true,
    'correlation_id', correlation_value,
    'idempotent_replay', false,
    'data', data_value
  );
$$;

create or replace function private.rpc_error_envelope(
  correlation_value text,
  category_value text,
  code_value text,
  message_value text,
  details_value jsonb
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'ok', false,
    'correlation_id', correlation_value,
    'idempotent_replay', false,
    'error', jsonb_build_object(
      'category', category_value,
      'code', code_value,
      'message', message_value,
      'retryable', false
    ) || case
      when details_value is null then '{}'::jsonb
      else jsonb_build_object('details', details_value)
    end
  );
$$;

-- Idempotency ---------------------------------------------------------------
-- The claim inserts a placeholder row inside the business transaction. A
-- concurrent request with the same key blocks on the primary key until the
-- first transaction settles, then reads the stored envelope (replay) or runs
-- itself if the first attempt rolled back. Replays require the same function,
-- request hash, and executor; anything else is a key reuse conflict.

create or replace function private.rpc_claim_idempotency(
  function_name_value text,
  idempotency_key_value uuid,
  request_hash_value text,
  executed_by_value uuid,
  out claim_outcome text,
  out stored_response jsonb
)
returns record
language plpgsql
set search_path = ''
as $$
declare
  existing private.idempotency_records%rowtype;
begin
  insert into private.idempotency_records (idempotency_key, function_name, request_hash, response, executed_by)
  values (idempotency_key_value, function_name_value, request_hash_value,
    jsonb_build_object('ok', false, 'pending', true), executed_by_value)
  on conflict (idempotency_key) do nothing;
  if found then
    claim_outcome := 'claimed';
    stored_response := null;
    return;
  end if;
  select * into strict existing
  from private.idempotency_records
  where idempotency_key = idempotency_key_value;
  if existing.function_name = function_name_value
    and existing.request_hash = request_hash_value
    and existing.executed_by = executed_by_value then
    claim_outcome := 'replay';
    stored_response := existing.response;
  else
    claim_outcome := 'reused';
    stored_response := null;
  end if;
end;
$$;

create or replace function private.rpc_store_idempotency(idempotency_key_value uuid, response_value jsonb)
returns void
language sql
set search_path = ''
as $$
  update private.idempotency_records
  set response = response_value
  where idempotency_key = idempotency_key_value;
$$;

-- Receiving input validation --------------------------------------------------
-- Shared by receiving_register and receiving_correct. Corrections replace the
-- whole business input, so both operations validate the same field set and no
-- partially validated state can be written.

create or replace function private.receiving_validate_input(input jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  source_type_value text;
  received_on_value date;
  orchard_id_value uuid;
  plot_id_value uuid;
  tree_id_value uuid;
  supplier_id_value uuid;
  supplier_reference_value text;
  origin_name_value text;
  variety_id_value uuid;
  total_weight_value numeric;
  container_count_big bigint;
  container_count_value integer;
  sorting_due_value date;
  worker_id_value uuid;
  deadline_days_value smallint;
begin
  source_type_value := private.rpc_input_text(input, 'source_type', true);
  if source_type_value not in ('harvest', 'purchase') then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '受入区分が正しくありません。',
      jsonb_build_object('field', 'source_type', 'reason', 'invalid_value'));
  end if;

  received_on_value := private.rpc_input_date(input, 'received_date', true);
  variety_id_value := private.rpc_input_uuid(input, 'variety_id', true);
  origin_name_value := private.rpc_input_text(input, 'origin_name', true);
  total_weight_value := private.rpc_input_weight(input, 'total_weight_kg', true, false);
  container_count_big := private.rpc_input_positive_int(input, 'container_count', true);
  if container_count_big > 2147483647 then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'container_count の値が範囲外です。',
      jsonb_build_object('field', 'container_count', 'reason', 'out_of_range'));
  end if;
  container_count_value := container_count_big::integer;
  worker_id_value := private.rpc_input_uuid(input, 'worker_id', true);
  sorting_due_value := private.rpc_input_date(input, 'sorting_due_date', false);

  if source_type_value = 'harvest' then
    orchard_id_value := private.rpc_input_uuid(input, 'orchard_id', true);
    plot_id_value := private.rpc_input_uuid(input, 'plot_id', true);
    tree_id_value := private.rpc_input_uuid(input, 'tree_id', true);
    if private.rpc_input_text(input, 'supplier_id', false) is not null
      or private.rpc_input_text(input, 'supplier_reference', false) is not null then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '収穫の受入に仕入先は指定できません。',
        jsonb_build_object('field', 'supplier_id', 'reason', 'not_allowed'));
    end if;
  else
    supplier_id_value := private.rpc_input_uuid(input, 'supplier_id', true);
    supplier_reference_value := private.rpc_input_text(input, 'supplier_reference', true);
    if private.rpc_input_text(input, 'orchard_id', false) is not null
      or private.rpc_input_text(input, 'plot_id', false) is not null
      or private.rpc_input_text(input, 'tree_id', false) is not null then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '仕入れの受入に産地区画・樹体は指定できません。',
        jsonb_build_object('field', 'tree_id', 'reason', 'not_allowed'));
    end if;
  end if;

  if not exists (select 1 from public.varieties v where v.id = variety_id_value and v.is_active) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '品種が見つからないか無効です。',
      jsonb_build_object('field', 'variety_id', 'reason', 'not_found'));
  end if;
  if not exists (select 1 from public.workers w where w.id = worker_id_value and w.is_active) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '担当者が見つからないか無効です。',
      jsonb_build_object('field', 'worker_id', 'reason', 'not_found'));
  end if;

  if source_type_value = 'harvest' then
    if not exists (select 1 from public.orchards o where o.id = orchard_id_value and o.is_active) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '農園が見つからないか無効です。',
        jsonb_build_object('field', 'orchard_id', 'reason', 'not_found'));
    end if;
    if not exists (
      select 1 from public.orchard_plots p
      where p.id = plot_id_value and p.is_active and p.orchard_id = orchard_id_value
    ) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '区画が農園に属していないか無効です。',
        jsonb_build_object('field', 'plot_id', 'reason', 'not_found'));
    end if;
    if not exists (
      select 1 from public.trees t
      where t.id = tree_id_value and t.is_active and t.plot_id = plot_id_value
    ) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '樹体が区画に属していないか無効です。',
        jsonb_build_object('field', 'tree_id', 'reason', 'not_found'));
    end if;
    if not exists (
      select 1 from public.trees t
      where t.id = tree_id_value and t.variety_id = variety_id_value
    ) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '樹体の品種が入力された品種と一致しません。',
        jsonb_build_object('field', 'tree_id', 'reason', 'variety_mismatch'));
    end if;
  else
    if not exists (select 1 from public.suppliers s where s.id = supplier_id_value and s.is_active) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '仕入先が見つからないか無効です。',
        jsonb_build_object('field', 'supplier_id', 'reason', 'not_found'));
    end if;
  end if;

  if sorting_due_value is null then
    select r.deadline_days into deadline_days_value
    from public.sorting_deadline_rules r
    where r.harvest_year = extract(year from received_on_value)::smallint
      and r.harvest_month = extract(month from received_on_value)::smallint
      and r.variety_id = variety_id_value
      and r.is_active;
    sorting_due_value := received_on_value + coalesce(deadline_days_value, 30::smallint)::integer;
  elsif sorting_due_value < received_on_value then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果期限は受入日以降の日付にしてください。',
      jsonb_build_object('field', 'sorting_due_date', 'reason', 'out_of_range'));
  end if;

  return jsonb_build_object(
    'source_type', source_type_value,
    'received_on', to_char(received_on_value, 'YYYY-MM-DD'),
    'orchard_id', orchard_id_value,
    'plot_id', plot_id_value,
    'tree_id', tree_id_value,
    'supplier_id', supplier_id_value,
    'supplier_reference', supplier_reference_value,
    'origin_name', origin_name_value,
    'variety_id', variety_id_value,
    'total_weight_kg', total_weight_value,
    'container_count', container_count_value,
    'sorting_due_on', to_char(sorting_due_value, 'YYYY-MM-DD'),
    'worker_id', worker_id_value
  );
end;
$$;

-- receiving_register ----------------------------------------------------------

create or replace function public.receiving_register(req jsonb)
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
  normalized jsonb;
  received_on_value date;
  display_id_value text;
  lot public.receiving_lots%rowtype;
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

  request_hash_value := encode(sha256(convert_to('receiving_register:' || input::text, 'utf8')), 'hex');
  select claim_outcome, stored_response
  into claim_outcome_value, stored_response_value
  from private.rpc_claim_idempotency('receiving_register', idempotency_key_value, request_hash_value, actor_id);
  if claim_outcome_value = 'replay' then
    return stored_response_value
      || jsonb_build_object('correlation_id', raw_correlation, 'idempotent_replay', true);
  end if;
  if claim_outcome_value = 'reused' then
    return private.rpc_error_envelope(raw_correlation, 'conflict', 'IDEMPOTENCY_KEY_REUSED',
      '同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。', null);
  end if;

  begin
    normalized := private.receiving_validate_input(input);
    received_on_value := (normalized ->> 'received_on')::date;
    display_id_value := private.next_display_id('受入', extract(year from received_on_value)::integer);

    insert into public.receiving_lots (
      display_id, source_type, received_on, orchard_id, plot_id, tree_id,
      supplier_id, supplier_reference, origin_name, variety_id,
      total_weight_kg, container_count, sorting_due_on, received_by,
      created_by, updated_by
    ) values (
      display_id_value,
      normalized ->> 'source_type',
      received_on_value,
      (normalized ->> 'orchard_id')::uuid,
      (normalized ->> 'plot_id')::uuid,
      (normalized ->> 'tree_id')::uuid,
      (normalized ->> 'supplier_id')::uuid,
      normalized ->> 'supplier_reference',
      normalized ->> 'origin_name',
      (normalized ->> 'variety_id')::uuid,
      (normalized ->> 'total_weight_kg')::public.weight_kg,
      (normalized ->> 'container_count')::integer,
      (normalized ->> 'sorting_due_on')::date,
      (normalized ->> 'worker_id')::uuid,
      actor_id,
      actor_id
    )
    returning * into lot;

    insert into public.change_history (
      entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
    ) values (
      'receiving_lot', lot.id, 'create', null, to_jsonb(lot), '受入登録', actor_id, correlation_value
    );

    envelope := private.rpc_success_envelope(raw_correlation, jsonb_build_object(
      'receiving_lot_id', lot.id,
      'display_id', lot.display_id,
      'status', lot.status,
      'received_date', to_char(lot.received_on, 'YYYY-MM-DD'),
      'sorting_due_date', to_char(lot.sorting_due_on, 'YYYY-MM-DD'),
      'version', lot.version
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

-- receiving_correct -----------------------------------------------------------

create or replace function public.receiving_correct(req jsonb)
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
  expected_version_value bigint;
  reason_value text;
  normalized jsonb;
  before_data_value jsonb;
  lot public.receiving_lots%rowtype;
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

  request_hash_value := encode(sha256(convert_to('receiving_correct:' || input::text, 'utf8')), 'hex');
  select claim_outcome, stored_response
  into claim_outcome_value, stored_response_value
  from private.rpc_claim_idempotency('receiving_correct', idempotency_key_value, request_hash_value, actor_id);
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
    expected_version_value := private.rpc_input_positive_int(input, 'expected_version', true);
    reason_value := private.rpc_input_text(input, 'reason', true);
    normalized := private.receiving_validate_input(input);

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
        'この受入ロットはすでに選果が確定されています。最新の状態を確認してください。',
        jsonb_build_object('current', jsonb_build_object(
          'receiving_lot_id', lot.id, 'status', lot.status, 'version', lot.version)));
    end if;
    if lot.version <> expected_version_value then
      perform private.rpc_fail('KW409', 'CONFLICT_STALE',
        'この受入ロットは他の操作で更新されています。最新の状態を確認してください。',
        jsonb_build_object('current', jsonb_build_object(
          'receiving_lot_id', lot.id, 'status', lot.status, 'version', lot.version)));
    end if;

    before_data_value := to_jsonb(lot);

    update public.receiving_lots set
      source_type = normalized ->> 'source_type',
      received_on = (normalized ->> 'received_on')::date,
      orchard_id = (normalized ->> 'orchard_id')::uuid,
      plot_id = (normalized ->> 'plot_id')::uuid,
      tree_id = (normalized ->> 'tree_id')::uuid,
      supplier_id = (normalized ->> 'supplier_id')::uuid,
      supplier_reference = normalized ->> 'supplier_reference',
      origin_name = normalized ->> 'origin_name',
      variety_id = (normalized ->> 'variety_id')::uuid,
      total_weight_kg = (normalized ->> 'total_weight_kg')::public.weight_kg,
      container_count = (normalized ->> 'container_count')::integer,
      sorting_due_on = (normalized ->> 'sorting_due_on')::date,
      received_by = (normalized ->> 'worker_id')::uuid,
      version = lot.version + 1
    where id = lot.id
    returning * into lot;

    insert into public.change_history (
      entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
    ) values (
      'receiving_lot', lot.id, 'correct', before_data_value, to_jsonb(lot), reason_value, actor_id, correlation_value
    );

    envelope := private.rpc_success_envelope(raw_correlation, jsonb_build_object(
      'receiving_lot_id', lot.id,
      'display_id', lot.display_id,
      'status', lot.status,
      'received_date', to_char(lot.received_on, 'YYYY-MM-DD'),
      'sorting_due_date', to_char(lot.sorting_due_on, 'YYYY-MM-DD'),
      'version', lot.version
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

-- Privileges ------------------------------------------------------------------

revoke all on function private.next_display_id(text, integer) from public, anon, authenticated;
revoke all on function private.rpc_fail(text, text, text, jsonb) from public, anon, authenticated;
revoke all on function private.rpc_try_uuid(text) from public, anon, authenticated;
revoke all on function private.rpc_try_uuid_v4(text) from public, anon, authenticated;
revoke all on function private.rpc_input_text(jsonb, text, boolean) from public, anon, authenticated;
revoke all on function private.rpc_input_uuid(jsonb, text, boolean) from public, anon, authenticated;
revoke all on function private.rpc_input_date(jsonb, text, boolean) from public, anon, authenticated;
revoke all on function private.rpc_input_weight(jsonb, text, boolean, boolean) from public, anon, authenticated;
revoke all on function private.rpc_input_positive_int(jsonb, text, boolean) from public, anon, authenticated;
revoke all on function private.rpc_success_envelope(text, jsonb) from public, anon, authenticated;
revoke all on function private.rpc_error_envelope(text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function private.rpc_claim_idempotency(text, uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.rpc_store_idempotency(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.receiving_validate_input(jsonb) from public, anon, authenticated;

revoke all on function public.receiving_register(jsonb) from public, anon;
revoke all on function public.receiving_correct(jsonb) from public, anon;
grant execute on function public.receiving_register(jsonb) to authenticated, service_role;
grant execute on function public.receiving_correct(jsonb) to authenticated, service_role;

comment on table private.display_id_counters is
  'Per-prefix, per-year sequence state used to issue immutable display IDs.';
comment on function public.receiving_register(jsonb) is
  'Registers a harvest or purchase receiving lot with common-envelope validation, idempotency, and audit history.';
comment on function public.receiving_correct(jsonb) is
  'Corrects an awaiting-sorting receiving lot with a mandatory reason, optimistic locking, and audit history.';

commit;
