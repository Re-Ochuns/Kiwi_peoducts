begin;

-- Master update RPCs -----------------------------------------------------------
-- master_register, master_update, master_deactivate, and master_activate share
-- one implementation in private.master_rpc keyed by input.master_type, reusing
-- the envelope, idempotency, and input helpers introduced with the receiving
-- RPCs. Masters are soft-deactivated so already referenced history stays
-- readable, and only active administrators may execute these functions.

-- Optimistic locking: masters gain the same version column contract as
-- receiving lots and containers. Existing rows start at version 1.

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'varieties','grades','orchards','orchard_plots','trees','suppliers','workers',
    'storage_locations','sorting_deadline_rules'
  ] loop
    execute format(
      'alter table public.%I add column version bigint not null default 1 check (version > 0)',
      table_name);
  end loop;
end;
$$;

create or replace function private.master_table(master_type_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case master_type_value
    when 'variety' then 'varieties'
    when 'grade' then 'grades'
    when 'orchard' then 'orchards'
    when 'orchard_plot' then 'orchard_plots'
    when 'tree' then 'trees'
    when 'supplier' then 'suppliers'
    when 'worker' then 'workers'
    when 'storage_location' then 'storage_locations'
    when 'sorting_deadline_rule' then 'sorting_deadline_rules'
  end;
$$;

-- Locks the target master row for the rest of the transaction.
create or replace function private.master_load(master_type_value text, master_id_value uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  row_json jsonb;
begin
  execute format('select to_jsonb(t) from public.%I t where t.id = $1 for update',
    private.master_table(master_type_value))
  using master_id_value
  into row_json;
  return row_json;
end;
$$;

-- Register locks parents with FOR SHARE so a concurrent master_deactivate of
-- the parent (FOR UPDATE) is serialized against child creation.
create or replace function private.master_require_active_parent(
  master_type_value text,
  parent_type_value text,
  parent_id_value uuid,
  field_name text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  parent_active boolean;
begin
  execute format('select t.is_active from public.%I t where t.id = $1 for share',
    private.master_table(parent_type_value))
  using parent_id_value
  into parent_active;
  if parent_active is distinct from true then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
      case parent_type_value
        when 'orchard' then '農園が見つからないか無効です。'
        when 'orchard_plot' then '区画が見つからないか無効です。'
        when 'variety' then '品種が見つからないか無効です。'
      end,
      jsonb_build_object('field', field_name, 'reason', 'not_found',
        'master_type', master_type_value));
  end if;
end;
$$;

-- Validates the type-specific business fields and returns the writable column
-- values. Update is a full replacement of the mutable fields; parent references
-- are immutable and may only be resent unchanged.
create or replace function private.master_validate(
  function_name_value text,
  master_type_value text,
  input jsonb,
  current_row jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  is_register boolean := function_name_value = 'master_register';
  normalized jsonb := '{}'::jsonb;
  parent_id uuid;
  int_value bigint;
  year_value bigint;
  month_value bigint;
  location_type_value text;
begin
  if master_type_value = 'variety' then
    normalized := jsonb_build_object(
      'code', private.rpc_input_text(input, 'code', true),
      'name', private.rpc_input_text(input, 'name', true));

  elsif master_type_value = 'grade' then
    if is_register then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED',
        '等級マスターは追加できません。表示順と有効・無効だけを変更できます。',
        jsonb_build_object('field', 'master_type', 'reason', 'not_allowed'));
    end if;
    int_value := private.rpc_input_positive_int(input, 'display_order', true);
    if int_value > 32767 then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'display_order の値が範囲外です。',
        jsonb_build_object('field', 'display_order', 'reason', 'out_of_range'));
    end if;
    normalized := jsonb_build_object('display_order', int_value);

  elsif master_type_value = 'orchard' then
    normalized := jsonb_build_object(
      'code', private.rpc_input_text(input, 'code', true),
      'name', private.rpc_input_text(input, 'name', true));

  elsif master_type_value = 'orchard_plot' then
    normalized := jsonb_build_object(
      'code', private.rpc_input_text(input, 'code', true),
      'name', private.rpc_input_text(input, 'name', true));
    parent_id := private.rpc_input_uuid(input, 'orchard_id', is_register);
    if is_register then
      perform private.master_require_active_parent(master_type_value, 'orchard', parent_id, 'orchard_id');
      normalized := normalized || jsonb_build_object('orchard_id', parent_id);
    elsif parent_id is not null and parent_id is distinct from (current_row ->> 'orchard_id')::uuid then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '区画の所属農園は変更できません。',
        jsonb_build_object('field', 'orchard_id', 'reason', 'immutable'));
    end if;

  elsif master_type_value = 'tree' then
    normalized := jsonb_build_object(
      'code', private.rpc_input_text(input, 'code', true),
      'name', private.rpc_input_text(input, 'name', true));
    parent_id := private.rpc_input_uuid(input, 'plot_id', is_register);
    if is_register then
      perform private.master_require_active_parent(master_type_value, 'orchard_plot', parent_id, 'plot_id');
      normalized := normalized || jsonb_build_object('plot_id', parent_id);
    elsif parent_id is not null and parent_id is distinct from (current_row ->> 'plot_id')::uuid then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '樹体の所属区画は変更できません。',
        jsonb_build_object('field', 'plot_id', 'reason', 'immutable'));
    end if;
    parent_id := private.rpc_input_uuid(input, 'variety_id', is_register);
    if is_register then
      perform private.master_require_active_parent(master_type_value, 'variety', parent_id, 'variety_id');
      normalized := normalized || jsonb_build_object('variety_id', parent_id);
    elsif parent_id is not null and parent_id is distinct from (current_row ->> 'variety_id')::uuid then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '樹体の品種は変更できません。',
        jsonb_build_object('field', 'variety_id', 'reason', 'immutable'));
    end if;

  elsif master_type_value = 'supplier' then
    normalized := jsonb_build_object(
      'management_code', private.rpc_input_text(input, 'management_code', true),
      'name', private.rpc_input_text(input, 'name', true));

  elsif master_type_value = 'worker' then
    normalized := jsonb_build_object(
      'code', private.rpc_input_text(input, 'code', true),
      'display_name', private.rpc_input_text(input, 'display_name', true));

  elsif master_type_value = 'storage_location' then
    location_type_value := private.rpc_input_text(input, 'location_type', true);
    if location_type_value not in ('cold_storage', 'other') then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '保管場所区分が正しくありません。',
        jsonb_build_object('field', 'location_type', 'reason', 'invalid_value'));
    end if;
    normalized := jsonb_build_object(
      'code', private.rpc_input_text(input, 'code', true),
      'name', private.rpc_input_text(input, 'name', true),
      'location_type', location_type_value);

  else -- sorting_deadline_rule
    int_value := private.rpc_input_positive_int(input, 'deadline_days', true);
    if int_value > 32767 then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'deadline_days の値が範囲外です。',
        jsonb_build_object('field', 'deadline_days', 'reason', 'out_of_range'));
    end if;
    normalized := jsonb_build_object('deadline_days', int_value);
    year_value := private.rpc_input_positive_int(input, 'harvest_year', is_register);
    month_value := private.rpc_input_positive_int(input, 'harvest_month', is_register);
    parent_id := private.rpc_input_uuid(input, 'variety_id', is_register);
    if is_register then
      if year_value not between 2000 and 9999 then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'harvest_year の値が範囲外です。',
          jsonb_build_object('field', 'harvest_year', 'reason', 'out_of_range'));
      end if;
      if month_value not between 1 and 12 then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'harvest_month の値が範囲外です。',
          jsonb_build_object('field', 'harvest_month', 'reason', 'out_of_range'));
      end if;
      perform private.master_require_active_parent(master_type_value, 'variety', parent_id, 'variety_id');
      normalized := normalized || jsonb_build_object(
        'harvest_year', year_value, 'harvest_month', month_value, 'variety_id', parent_id);
    else
      if year_value is not null and year_value is distinct from (current_row ->> 'harvest_year')::bigint then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果期限ルールの適用年度は変更できません。',
          jsonb_build_object('field', 'harvest_year', 'reason', 'immutable'));
      end if;
      if month_value is not null and month_value is distinct from (current_row ->> 'harvest_month')::bigint then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果期限ルールの収穫月は変更できません。',
          jsonb_build_object('field', 'harvest_month', 'reason', 'immutable'));
      end if;
      parent_id := private.rpc_input_uuid(input, 'variety_id', false);
      if parent_id is not null and parent_id is distinct from (current_row ->> 'variety_id')::uuid then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '選果期限ルールの品種は変更できません。',
          jsonb_build_object('field', 'variety_id', 'reason', 'immutable'));
      end if;
    end if;
  end if;

  return normalized;
end;
$$;

-- Duplicate pre-checks give field-level details before the insert or update.
-- effective_row is the would-be row (current row merged with the new values),
-- so composite keys can mix immutable current columns with changed ones.
create or replace function private.master_check_duplicates(
  master_type_value text,
  effective_row jsonb,
  exclude_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  existing_id uuid;
  existing_active boolean;
  dup_field text;
begin
  if master_type_value = 'variety' then
    dup_field := 'code';
    select v.id, v.is_active into existing_id, existing_active
    from public.varieties v
    where v.code = effective_row ->> 'code' and (exclude_id is null or v.id <> exclude_id);
    if existing_id is null then
      dup_field := 'name';
      select v.id, v.is_active into existing_id, existing_active
      from public.varieties v
      where v.name = effective_row ->> 'name' and (exclude_id is null or v.id <> exclude_id);
    end if;
  elsif master_type_value = 'grade' then
    dup_field := 'display_order';
    select g.id, g.is_active into existing_id, existing_active
    from public.grades g
    where g.display_order = (effective_row ->> 'display_order')::smallint
      and (exclude_id is null or g.id <> exclude_id);
  elsif master_type_value = 'orchard' then
    dup_field := 'code';
    select o.id, o.is_active into existing_id, existing_active
    from public.orchards o
    where o.code = effective_row ->> 'code' and (exclude_id is null or o.id <> exclude_id);
  elsif master_type_value = 'orchard_plot' then
    dup_field := 'code';
    select p.id, p.is_active into existing_id, existing_active
    from public.orchard_plots p
    where p.orchard_id = (effective_row ->> 'orchard_id')::uuid
      and p.code = effective_row ->> 'code'
      and (exclude_id is null or p.id <> exclude_id);
  elsif master_type_value = 'tree' then
    dup_field := 'code';
    select t.id, t.is_active into existing_id, existing_active
    from public.trees t
    where t.plot_id = (effective_row ->> 'plot_id')::uuid
      and t.code = effective_row ->> 'code'
      and (exclude_id is null or t.id <> exclude_id);
  elsif master_type_value = 'supplier' then
    dup_field := 'management_code';
    select s.id, s.is_active into existing_id, existing_active
    from public.suppliers s
    where s.management_code = effective_row ->> 'management_code'
      and (exclude_id is null or s.id <> exclude_id);
  elsif master_type_value = 'worker' then
    dup_field := 'code';
    select w.id, w.is_active into existing_id, existing_active
    from public.workers w
    where w.code = effective_row ->> 'code' and (exclude_id is null or w.id <> exclude_id);
  elsif master_type_value = 'storage_location' then
    dup_field := 'code';
    select l.id, l.is_active into existing_id, existing_active
    from public.storage_locations l
    where l.code = effective_row ->> 'code' and (exclude_id is null or l.id <> exclude_id);
  else -- sorting_deadline_rule
    dup_field := 'variety_id';
    select r.id, r.is_active into existing_id, existing_active
    from public.sorting_deadline_rules r
    where r.harvest_year = (effective_row ->> 'harvest_year')::smallint
      and r.harvest_month = (effective_row ->> 'harvest_month')::smallint
      and r.variety_id = (effective_row ->> 'variety_id')::uuid
      and (exclude_id is null or r.id <> exclude_id);
  end if;

  if existing_id is not null then
    perform private.rpc_fail('KW400', 'MASTER_DUPLICATE',
      'すでに同じ値で登録されています。無効化済みの場合は再有効化してください。',
      jsonb_build_object('field', dup_field, 'reason', 'duplicate',
        'existing', jsonb_build_object('master_id', existing_id, 'is_active', existing_active)));
  end if;
end;
$$;

-- Deactivation is blocked while active dependents remain, so an active child
-- can never point at an inactive parent and referenced rows are never lost.
create or replace function private.master_guard_dependents(
  master_type_value text,
  master_id_value uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  deps jsonb := '[]'::jsonb;
  active_count bigint;
begin
  if master_type_value = 'orchard' then
    select count(*) into active_count
    from public.orchard_plots p where p.orchard_id = master_id_value and p.is_active;
    if active_count > 0 then
      deps := deps || jsonb_build_object('entity', 'orchard_plot', 'active_count', active_count);
    end if;
  elsif master_type_value = 'orchard_plot' then
    select count(*) into active_count
    from public.trees t where t.plot_id = master_id_value and t.is_active;
    if active_count > 0 then
      deps := deps || jsonb_build_object('entity', 'tree', 'active_count', active_count);
    end if;
  elsif master_type_value = 'variety' then
    select count(*) into active_count
    from public.trees t where t.variety_id = master_id_value and t.is_active;
    if active_count > 0 then
      deps := deps || jsonb_build_object('entity', 'tree', 'active_count', active_count);
    end if;
    select count(*) into active_count
    from public.sorting_deadline_rules r where r.variety_id = master_id_value and r.is_active;
    if active_count > 0 then
      deps := deps || jsonb_build_object('entity', 'sorting_deadline_rule', 'active_count', active_count);
    end if;
  elsif master_type_value = 'storage_location' then
    select count(*) into active_count
    from public.containers c
    where c.location_id = master_id_value and c.status not in ('shipped', 'expired');
    if active_count > 0 then
      deps := deps || jsonb_build_object('entity', 'container', 'active_count', active_count);
    end if;
  end if;

  if jsonb_array_length(deps) > 0 then
    perform private.rpc_fail('KW400', 'MASTER_IN_USE',
      '使用中のため無効化できません。先に関連するデータを無効化または整理してください。',
      jsonb_build_object('master_id', master_id_value, 'dependencies', deps));
  end if;
end;
$$;

-- Reactivation requires active parents. FOR SHARE on the parent serializes
-- this check against a concurrent master_deactivate of the parent.
create or replace function private.master_guard_parents_active(
  master_type_value text,
  current_row jsonb
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  parent_types text[];
  parent_fields text[];
  parent_type text;
  parent_id uuid;
  parent_active boolean;
begin
  if master_type_value = 'orchard_plot' then
    parent_types := array['orchard'];
    parent_fields := array['orchard_id'];
  elsif master_type_value = 'tree' then
    parent_types := array['orchard_plot', 'variety'];
    parent_fields := array['plot_id', 'variety_id'];
  elsif master_type_value = 'sorting_deadline_rule' then
    parent_types := array['variety'];
    parent_fields := array['variety_id'];
  else
    return;
  end if;

  for idx in 1 .. array_length(parent_types, 1) loop
    parent_type := parent_types[idx];
    parent_id := (current_row ->> parent_fields[idx])::uuid;
    execute format('select t.is_active from public.%I t where t.id = $1 for share',
      private.master_table(parent_type))
    using parent_id
    into parent_active;
    if parent_active is distinct from true then
      perform private.rpc_fail('KW400', 'MASTER_PARENT_INACTIVE',
        '上位マスターが無効のため有効化できません。先に上位マスターを有効化してください。',
        jsonb_build_object('field', parent_fields[idx],
          'parent', jsonb_build_object('master_type', parent_type, 'master_id', parent_id)));
    end if;
  end loop;
end;
$$;

create or replace function private.master_insert(
  master_type_value text,
  normalized jsonb,
  actor_id_value uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  table_name text := private.master_table(master_type_value);
  column_list text;
  select_list text;
  row_json jsonb;
begin
  select string_agg(format('%I', k.column_name), ', '),
         string_agg(format('r.%I', k.column_name), ', ')
  into column_list, select_list
  from jsonb_object_keys(normalized) as k(column_name);
  execute format(
    'insert into public.%1$I as t (%2$s, created_by, updated_by)
     select %3$s, $2, $2 from jsonb_populate_record(null::public.%1$I, $1) as r
     returning to_jsonb(t)',
    table_name, column_list, select_list)
  using normalized, actor_id_value
  into row_json;
  return row_json;
end;
$$;

create or replace function private.master_apply_update(
  master_type_value text,
  master_id_value uuid,
  normalized jsonb,
  new_version bigint
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  table_name text := private.master_table(master_type_value);
  set_list text;
  row_json jsonb;
begin
  select string_agg(format('%1$I = r.%1$I', k.column_name), ', ')
  into set_list
  from jsonb_object_keys(normalized) as k(column_name);
  execute format(
    'update public.%1$I t set %2$s, version = $3
     from jsonb_populate_record(null::public.%1$I, $1) as r
     where t.id = $2
     returning to_jsonb(t)',
    table_name, set_list)
  using normalized, master_id_value, new_version
  into row_json;
  return row_json;
end;
$$;

create or replace function private.master_apply_set_active(
  master_type_value text,
  master_id_value uuid,
  active_value boolean,
  new_version bigint
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  row_json jsonb;
begin
  execute format(
    'update public.%I t set is_active = $2, version = $3 where t.id = $1 returning to_jsonb(t)',
    private.master_table(master_type_value))
  using master_id_value, active_value, new_version
  into row_json;
  return row_json;
end;
$$;

create or replace function private.master_rpc(function_name_value text, req jsonb)
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
  master_type_value text;
  master_id_value uuid;
  expected_version_value bigint;
  reason_value text;
  normalized jsonb;
  current_row jsonb;
  row_json jsonb;
  history_operation text;
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
  if not private.current_user_has_role('administrator') then
    return private.rpc_error_envelope(raw_correlation, 'auth', 'AUTH_FORBIDDEN',
      'マスターの変更は管理者だけが行えます。', null);
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
    master_type_value := private.rpc_input_text(input, 'master_type', true);
    if private.master_table(master_type_value) is null then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', 'master_type が正しくありません。',
        jsonb_build_object('field', 'master_type', 'reason', 'invalid_value'));
    end if;

    if function_name_value = 'master_register' then
      reason_value := coalesce(private.rpc_input_text(input, 'reason', false), 'マスター登録');
      normalized := private.master_validate(function_name_value, master_type_value, input, null);
      perform private.master_check_duplicates(master_type_value, normalized, null);
      row_json := private.master_insert(master_type_value, normalized, actor_id);
      history_operation := 'create';
      current_row := null;
    else
      master_id_value := private.rpc_input_uuid(input, 'master_id', true);
      expected_version_value := private.rpc_input_positive_int(input, 'expected_version', true);
      reason_value := private.rpc_input_text(input, 'reason', true);

      current_row := private.master_load(master_type_value, master_id_value);
      if current_row is null then
        perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '対象のマスターが見つかりません。',
          jsonb_build_object('field', 'master_id', 'reason', 'not_found'));
      end if;
      if (current_row ->> 'version')::bigint <> expected_version_value then
        perform private.rpc_fail('KW409', 'CONFLICT_STALE',
          'このマスターは他の操作で更新されています。最新の状態を確認してください。',
          jsonb_build_object('current', jsonb_build_object(
            'master_id', master_id_value,
            'is_active', (current_row ->> 'is_active')::boolean,
            'version', (current_row ->> 'version')::bigint)));
      end if;

      if function_name_value = 'master_update' then
        normalized := private.master_validate(function_name_value, master_type_value, input, current_row);
        perform private.master_check_duplicates(master_type_value, current_row || normalized, master_id_value);
        row_json := private.master_apply_update(
          master_type_value, master_id_value, normalized, expected_version_value + 1);
        history_operation := 'update';
      elsif function_name_value = 'master_deactivate' then
        if not (current_row ->> 'is_active')::boolean then
          perform private.rpc_fail('KW409', 'CONFLICT_STALE',
            'このマスターはすでに無効化されています。最新の状態を確認してください。',
            jsonb_build_object('current', jsonb_build_object(
              'master_id', master_id_value, 'is_active', false,
              'version', (current_row ->> 'version')::bigint)));
        end if;
        perform private.master_guard_dependents(master_type_value, master_id_value);
        row_json := private.master_apply_set_active(
          master_type_value, master_id_value, false, expected_version_value + 1);
        history_operation := 'transition';
      else -- master_activate
        if (current_row ->> 'is_active')::boolean then
          perform private.rpc_fail('KW409', 'CONFLICT_STALE',
            'このマスターはすでに有効です。最新の状態を確認してください。',
            jsonb_build_object('current', jsonb_build_object(
              'master_id', master_id_value, 'is_active', true,
              'version', (current_row ->> 'version')::bigint)));
        end if;
        perform private.master_guard_parents_active(master_type_value, current_row);
        row_json := private.master_apply_set_active(
          master_type_value, master_id_value, true, expected_version_value + 1);
        history_operation := 'transition';
      end if;
    end if;

    insert into public.change_history (
      entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
    ) values (
      'master',
      (row_json ->> 'id')::uuid,
      history_operation,
      case when current_row is null then null
        else current_row || jsonb_build_object('master_type', master_type_value) end,
      row_json || jsonb_build_object('master_type', master_type_value),
      reason_value,
      actor_id,
      correlation_value
    );

    envelope := private.rpc_success_envelope(raw_correlation,
      jsonb_build_object('master_type', master_type_value, 'master_id', row_json ->> 'id')
      || (row_json - 'id' - 'created_at' - 'created_by' - 'updated_at' - 'updated_by'));
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
    when unique_violation then
      envelope := private.rpc_error_envelope(raw_correlation, 'business', 'MASTER_DUPLICATE',
        'すでに同じ値で登録されています。最新の一覧を確認してください。',
        jsonb_build_object('reason', 'duplicate'));
  end;

  perform private.rpc_store_idempotency(idempotency_key_value, envelope);
  return envelope;
end;
$$;

-- Public entry points centralize the common-contract server log so every
-- response path (validation, auth, replay, conflict, and success) is covered.
create or replace function public.master_register(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.rpc_log_response(
    'master_register', auth.uid(),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'correlation_id'),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'idempotency_key'),
    private.master_rpc('master_register', req));
$$;

create or replace function public.master_update(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.rpc_log_response(
    'master_update', auth.uid(),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'correlation_id'),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'idempotency_key'),
    private.master_rpc('master_update', req));
$$;

create or replace function public.master_deactivate(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.rpc_log_response(
    'master_deactivate', auth.uid(),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'correlation_id'),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'idempotency_key'),
    private.master_rpc('master_deactivate', req));
$$;

create or replace function public.master_activate(req jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.rpc_log_response(
    'master_activate', auth.uid(),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'correlation_id'),
    private.rpc_try_uuid_v4(req -> 'meta' ->> 'idempotency_key'),
    private.master_rpc('master_activate', req));
$$;

-- Privileges ------------------------------------------------------------------

revoke all on function private.master_table(text) from public, anon, authenticated;
revoke all on function private.master_load(text, uuid) from public, anon, authenticated;
revoke all on function private.master_require_active_parent(text, text, uuid, text) from public, anon, authenticated;
revoke all on function private.master_validate(text, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.master_check_duplicates(text, jsonb, uuid) from public, anon, authenticated;
revoke all on function private.master_guard_dependents(text, uuid) from public, anon, authenticated;
revoke all on function private.master_guard_parents_active(text, jsonb) from public, anon, authenticated;
revoke all on function private.master_insert(text, jsonb, uuid) from public, anon, authenticated;
revoke all on function private.master_apply_update(text, uuid, jsonb, bigint) from public, anon, authenticated;
revoke all on function private.master_apply_set_active(text, uuid, boolean, bigint) from public, anon, authenticated;
revoke all on function private.master_rpc(text, jsonb) from public, anon, authenticated;

revoke all on function public.master_register(jsonb) from public, anon;
revoke all on function public.master_update(jsonb) from public, anon;
revoke all on function public.master_deactivate(jsonb) from public, anon;
revoke all on function public.master_activate(jsonb) from public, anon;
grant execute on function public.master_register(jsonb) to authenticated, service_role;
grant execute on function public.master_update(jsonb) to authenticated, service_role;
grant execute on function public.master_deactivate(jsonb) to authenticated, service_role;
grant execute on function public.master_activate(jsonb) to authenticated, service_role;

comment on function public.master_register(jsonb) is
  'Registers a stage 1 master row (administrator only) with common-envelope validation, idempotency, and audit history.';
comment on function public.master_update(jsonb) is
  'Replaces the mutable fields of a stage 1 master row with a mandatory reason, optimistic locking, and audit history.';
comment on function public.master_deactivate(jsonb) is
  'Soft-deactivates a stage 1 master row instead of deleting it, guarding active dependents, with reason and audit history.';
comment on function public.master_activate(jsonb) is
  'Reactivates a deactivated stage 1 master row, requiring active parents, with reason and audit history.';

commit;
