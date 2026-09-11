begin;

create table public.csv_export_audits (
  export_id uuid primary key,
  correlation_id uuid not null,
  exported_by uuid not null references public.profiles(id) on delete restrict,
  dataset text not null check (dataset in ('inventory', 'masters', 'history', 'invalid')),
  filters jsonb not null default '{}'::jsonb check (jsonb_typeof(filters) = 'object'),
  generated_at timestamptz not null default now(),
  row_count integer check (row_count is null or row_count >= 0),
  byte_count integer check (byte_count is null or byte_count >= 0),
  result_code text not null check (
    result_code in ('SUCCESS', 'VALIDATION_FAILED', 'EXPORT_LIMIT_EXCEEDED')
  )
);

create index csv_export_audits_exported_at_idx
on public.csv_export_audits (exported_by, generated_at desc);

create trigger csv_export_audits_append_only
before update or delete on public.csv_export_audits
for each row execute function private.prevent_history_mutation();

alter table public.csv_export_audits enable row level security;
revoke all on public.csv_export_audits from public, anon, authenticated;
grant select on public.csv_export_audits to authenticated;
grant all on public.csv_export_audits to service_role;

create policy "active administrators can read csv export audits"
on public.csv_export_audits for select to authenticated
using (private.current_user_has_role('administrator'));

create or replace function private.csv_validate_filter_keys(
  filters_value jsonb,
  allowed_keys text[]
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  key_value text;
begin
  if filters_value is null or jsonb_typeof(filters_value) <> 'object' then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', 'filters の形式が正しくありません。',
      jsonb_build_object('field', 'filters', 'reason', 'invalid_type'));
  end if;
  for key_value in select jsonb_object_keys(filters_value)
  loop
    if not (key_value = any(allowed_keys)) then
      perform private.rpc_fail(
        'KW400', 'VALIDATION_FAILED', '未対応の出力条件が指定されています。',
        jsonb_build_object('field', 'filters.' || key_value, 'reason', 'unknown_field'));
    end if;
  end loop;
end;
$$;

create or replace function private.csv_cell(value text, protect_formula boolean default true)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  safe_value text := coalesce(value, '');
  probe text;
  stripped text;
  dangerous boolean := false;
begin
  probe := safe_value;
  if left(safe_value, 1) in (E'\t', E'\r', E'\n') then
    dangerous := true;
  end if;
  loop
    stripped := regexp_replace(probe, '^[[:space:][:cntrl:]]+', '');
    stripped := ltrim(stripped, chr(65279));
    exit when stripped = probe;
    probe := stripped;
  end loop;
  if protect_formula and (
    dangerous or left(probe, 1) in ('=', '+', '-', '@', '＝', '＋', '－', '＠')
  ) then
    safe_value := '''' || safe_value;
  end if;
  return '"' || replace(safe_value, '"', '""') || '"';
end;
$$;

create or replace function private.csv_timestamp_jst(value timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when value is null then null else
    to_char(value at time zone 'Asia/Tokyo', 'YYYY-MM-DD"T"HH24:MI:SS.MS') || '+09:00'
  end;
$$;

create or replace function private.csv_inventory_payload(filters_value jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  search_value text;
  status_value text;
  sort_value text;
  row_count_value integer;
  body_value text;
  header_value constant text := '"在庫内部ID","在庫ID","品種","等級","元重量kg","現在重量kg","予約重量kg","利用可能重量kg","状態コード","保管場所コード","保管場所名","更新日時JST"';
begin
  perform private.csv_validate_filter_keys(filters_value, array['search', 'status', 'sort']);
  search_value := coalesce(private.rpc_input_text(filters_value, 'search', false), '');
  status_value := private.rpc_input_text(filters_value, 'status', false);
  sort_value := coalesce(private.rpc_input_text(filters_value, 'sort', false), 'updated_desc');
  if length(search_value) > 100 then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '検索文字列は100文字以内で入力してください。',
      jsonb_build_object('field', 'filters.search', 'reason', 'too_long'));
  end if;
  if status_value is not null and status_value not in (
    'awaiting_label', 'cold_storage', 'ethylene_processing', 'resting',
    'awaiting_ripeness_check', 'shippable', 'shipped', 'expired'
  ) then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '在庫状態が正しくありません。',
      jsonb_build_object('field', 'filters.status', 'reason', 'invalid_value'));
  end if;
  if sort_value not in ('updated_desc', 'display_id_asc', 'current_weight_desc') then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '並び順が正しくありません。',
      jsonb_build_object('field', 'filters.sort', 'reason', 'invalid_value'));
  end if;

  select count(*)::integer,
    coalesce(string_agg(rows.row_text, E'\r\n' order by rows.seq), '')
  into row_count_value, body_value
  from (
    select row_number() over (
      order by
        case when sort_value = 'updated_desc' then c.updated_at end desc,
        case when sort_value = 'updated_desc' then c.display_id end,
        case when sort_value = 'display_id_asc' then c.display_id end,
        case when sort_value = 'current_weight_desc' then c.current_weight_kg end desc,
        case when sort_value = 'current_weight_desc' then c.display_id end,
        c.id
    ) as seq,
    array_to_string(array[
      private.csv_cell(c.id::text, false),
      private.csv_cell(c.display_id),
      private.csv_cell(v.name),
      private.csv_cell(g.code),
      private.csv_cell(to_char(c.original_weight_kg, 'FM9999999990.00'), false),
      private.csv_cell(to_char(c.current_weight_kg, 'FM9999999990.00'), false),
      private.csv_cell(to_char(c.reserved_weight_kg, 'FM9999999990.00'), false),
      private.csv_cell(to_char(c.current_weight_kg - c.reserved_weight_kg, 'FM9999999990.00'), false),
      private.csv_cell(c.status),
      private.csv_cell(l.code),
      private.csv_cell(l.name),
      private.csv_cell(private.csv_timestamp_jst(c.updated_at), false)
    ], ',') as row_text
    from public.containers c
    join public.varieties v on v.id = c.variety_id
    join public.grades g on g.id = c.grade_id
    left join public.storage_locations l on l.id = c.location_id
    where (search_value = '' or c.display_id ilike '%' || search_value || '%')
      and (status_value is null or c.status = status_value)
    order by
      case when sort_value = 'updated_desc' then c.updated_at end desc,
      case when sort_value = 'updated_desc' then c.display_id end,
      case when sort_value = 'display_id_asc' then c.display_id end,
      case when sort_value = 'current_weight_desc' then c.current_weight_kg end desc,
      case when sort_value = 'current_weight_desc' then c.display_id end,
      c.id
    limit 10001
  ) rows;

  return jsonb_build_object(
    'row_count', row_count_value,
    'csv', chr(65279) || header_value || E'\r\n'
      || case when body_value = '' then '' else body_value || E'\r\n' end);
end;
$$;

create or replace function private.csv_master_search_text(
  master_type_value text,
  row_value jsonb
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  result_value text;
begin
  result_value := case master_type_value
    when 'variety' then concat_ws(' ', row_value ->> 'code', row_value ->> 'name')
    when 'grade' then concat_ws(' ', row_value ->> 'code', row_value ->> 'display_order')
    when 'orchard' then concat_ws(' ', row_value ->> 'code', row_value ->> 'name')
    when 'orchard_plot' then concat_ws(
      ' ', row_value ->> 'orchard_id', row_value ->> 'code', row_value ->> 'name')
    when 'tree' then concat_ws(
      ' ', row_value ->> 'plot_id', row_value ->> 'variety_id',
      row_value ->> 'code', row_value ->> 'name')
    when 'supplier' then concat_ws(
      ' ', row_value ->> 'management_code', row_value ->> 'name')
    when 'worker' then concat_ws(
      ' ', row_value ->> 'code', row_value ->> 'display_name')
    when 'storage_location' then concat_ws(
      ' ', row_value ->> 'code', row_value ->> 'name', row_value ->> 'location_type',
      case row_value ->> 'location_type'
        when 'cold_storage' then '冷蔵庫'
        else 'その他'
      end)
    when 'sorting_deadline_rule' then concat_ws(
      ' ', row_value ->> 'harvest_year', row_value ->> 'harvest_month',
      row_value ->> 'variety_id', row_value ->> 'deadline_days')
    else ''
  end;
  if master_type_value = 'orchard_plot' then
    select concat_ws(' ', result_value, o.code, o.name) into result_value
    from public.orchards o where o.id = (row_value ->> 'orchard_id')::uuid;
  elsif master_type_value = 'tree' then
    select concat_ws(' ', result_value, p.code, p.name, v.code, v.name)
    into result_value
    from public.orchard_plots p
    join public.varieties v on v.id = (row_value ->> 'variety_id')::uuid
    where p.id = (row_value ->> 'plot_id')::uuid;
  elsif master_type_value = 'sorting_deadline_rule' then
    select concat_ws(' ', result_value, v.code, v.name) into result_value
    from public.varieties v where v.id = (row_value ->> 'variety_id')::uuid;
  else
    result_value := concat_ws(' ', result_value, '—');
  end if;
  return coalesce(result_value, '');
end;
$$;

create or replace function private.csv_master_header(master_type_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case master_type_value
    when 'variety' then '"内部ID","コード","品種名","有効","バージョン","更新日時JST"'
    when 'grade' then '"内部ID","等級コード","表示順","有効","バージョン","更新日時JST"'
    when 'orchard' then '"内部ID","コード","農園名","有効","バージョン","更新日時JST"'
    when 'orchard_plot' then '"内部ID","農園内部ID","コード","区画名","有効","バージョン","更新日時JST"'
    when 'tree' then '"内部ID","区画内部ID","品種内部ID","コード","樹体名","有効","バージョン","更新日時JST"'
    when 'supplier' then '"内部ID","管理コード","仕入先名","有効","バージョン","更新日時JST"'
    when 'worker' then '"内部ID","コード","作業者名","有効","バージョン","更新日時JST"'
    when 'storage_location' then '"内部ID","コード","保管場所名","場所種別","有効","バージョン","更新日時JST"'
    when 'sorting_deadline_rule' then '"内部ID","収穫年","収穫月","品種内部ID","期限日数","有効","バージョン","更新日時JST"'
  end;
$$;

create or replace function private.csv_master_row(
  master_type_value text,
  row_value jsonb
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  cells text[];
begin
  cells := case master_type_value
    when 'variety' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'code'),
      private.csv_cell(row_value ->> 'name')]
    when 'grade' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'code'),
      private.csv_cell(row_value ->> 'display_order', false)]
    when 'orchard' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'code'),
      private.csv_cell(row_value ->> 'name')]
    when 'orchard_plot' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'orchard_id', false),
      private.csv_cell(row_value ->> 'code'), private.csv_cell(row_value ->> 'name')]
    when 'tree' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'plot_id', false),
      private.csv_cell(row_value ->> 'variety_id', false), private.csv_cell(row_value ->> 'code'),
      private.csv_cell(row_value ->> 'name')]
    when 'supplier' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'management_code'),
      private.csv_cell(row_value ->> 'name')]
    when 'worker' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'code'),
      private.csv_cell(row_value ->> 'display_name')]
    when 'storage_location' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'code'),
      private.csv_cell(row_value ->> 'name'), private.csv_cell(row_value ->> 'location_type')]
    when 'sorting_deadline_rule' then array[
      private.csv_cell(row_value ->> 'id', false), private.csv_cell(row_value ->> 'harvest_year', false),
      private.csv_cell(row_value ->> 'harvest_month', false),
      private.csv_cell(row_value ->> 'variety_id', false),
      private.csv_cell(row_value ->> 'deadline_days', false)]
  end;
  cells := cells || array[
    private.csv_cell(row_value ->> 'is_active', false),
    private.csv_cell(row_value ->> 'version', false),
    private.csv_cell(private.csv_timestamp_jst((row_value ->> 'updated_at')::timestamptz), false)
  ];
  return array_to_string(cells, ',');
end;
$$;

create or replace function private.csv_master_payload(filters_value jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  master_type_value text;
  search_value text;
  active_value text;
  table_value text;
  order_value text;
  rows_value jsonb;
  row_count_value integer;
  body_value text;
  query_value text;
begin
  perform private.csv_validate_filter_keys(
    filters_value, array['master_type', 'search', 'active']);
  master_type_value := private.rpc_input_text(filters_value, 'master_type', true);
  search_value := lower(coalesce(private.rpc_input_text(filters_value, 'search', false), ''));
  active_value := coalesce(private.rpc_input_text(filters_value, 'active', false), 'active');
  table_value := private.master_table(master_type_value);
  if table_value is null then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', 'マスターの種類が正しくありません。',
      jsonb_build_object('field', 'filters.master_type', 'reason', 'invalid_value'));
  end if;
  if length(search_value) > 100 then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '検索文字列は100文字以内で入力してください。',
      jsonb_build_object('field', 'filters.search', 'reason', 'too_long'));
  end if;
  if active_value not in ('all', 'active', 'inactive') then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '有効状態が正しくありません。',
      jsonb_build_object('field', 'filters.active', 'reason', 'invalid_value'));
  end if;

  order_value := case master_type_value
    when 'grade' then 't.display_order, t.id'
    when 'sorting_deadline_rule' then 't.harvest_year, t.harvest_month, t.variety_id, t.id'
    when 'supplier' then 't.management_code, t.id'
    else 't.code, t.id'
  end;
  query_value := format($query$
    select coalesce(jsonb_agg(rows.row_value order by rows.seq), '[]'::jsonb)
    from (
      select row_number() over (order by %1$s) as seq, to_jsonb(t) as row_value
      from public.%2$I t
      where ($1 = 'all' or ($1 = 'active' and t.is_active) or ($1 = 'inactive' and not t.is_active))
        and ($2 = '' or position($2 in lower(private.csv_master_search_text($3, to_jsonb(t)))) > 0)
      order by %1$s
      limit 10001
    ) rows
  $query$, order_value, table_value);
  execute query_value using active_value, search_value, master_type_value into rows_value;

  row_count_value := jsonb_array_length(rows_value);
  select coalesce(string_agg(
    private.csv_master_row(master_type_value, item.value), E'\r\n' order by item.ordinality), '')
  into body_value
  from jsonb_array_elements(rows_value) with ordinality as item(value, ordinality);

  return jsonb_build_object(
    'row_count', row_count_value,
    'csv', chr(65279) || private.csv_master_header(master_type_value) || E'\r\n'
      || case when body_value = '' then '' else body_value || E'\r\n' end);
end;
$$;

create or replace function private.csv_history_payload(filters_value jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  entity_type_value text;
  entity_id_value uuid;
  from_date_value date;
  to_date_value date;
  row_count_value integer;
  body_value text;
  header_value constant text := '"履歴ID","対象種別","対象内部ID","操作","変更前JSON","変更後JSON","理由","変更日時JST","変更者内部ID","変更者名","相関ID"';
begin
  perform private.csv_validate_filter_keys(
    filters_value, array['entity_type', 'entity_id', 'from_date', 'to_date']);
  entity_type_value := private.rpc_input_text(filters_value, 'entity_type', false);
  entity_id_value := private.rpc_input_uuid(filters_value, 'entity_id', false);
  from_date_value := private.rpc_input_date(filters_value, 'from_date', false);
  to_date_value := private.rpc_input_date(filters_value, 'to_date', false);
  if entity_type_value is not null and entity_type_value not in (
    'master', 'receiving_lot', 'sorting_result', 'container', 'label_job'
  ) then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '履歴の対象種別が正しくありません。',
      jsonb_build_object('field', 'filters.entity_type', 'reason', 'invalid_value'));
  end if;
  if from_date_value is not null and to_date_value is not null
    and from_date_value > to_date_value then
    perform private.rpc_fail(
      'KW400', 'VALIDATION_FAILED', '開始日は終了日以前を指定してください。',
      jsonb_build_object('field', 'filters.from_date', 'reason', 'invalid_range'));
  end if;

  select count(*)::integer,
    coalesce(string_agg(rows.row_text, E'\r\n' order by rows.seq), '')
  into row_count_value, body_value
  from (
    select row_number() over (order by h.changed_at desc, h.id desc) as seq,
      array_to_string(array[
        private.csv_cell(h.id::text, false),
        private.csv_cell(h.entity_type),
        private.csv_cell(h.entity_id::text, false),
        private.csv_cell(h.operation),
        private.csv_cell(h.before_data::text),
        private.csv_cell(h.after_data::text),
        private.csv_cell(h.reason),
        private.csv_cell(private.csv_timestamp_jst(h.changed_at), false),
        private.csv_cell(h.changed_by::text, false),
        private.csv_cell(p.display_name),
        private.csv_cell(h.correlation_id::text, false)
      ], ',') as row_text
    from public.change_history h
    join public.profiles p on p.id = h.changed_by
    where (entity_type_value is null or h.entity_type = entity_type_value)
      and (entity_id_value is null or h.entity_id = entity_id_value)
      and (from_date_value is null or h.changed_at >= (from_date_value::timestamp at time zone 'Asia/Tokyo'))
      and (to_date_value is null or h.changed_at < ((to_date_value + 1)::timestamp at time zone 'Asia/Tokyo'))
    order by h.changed_at desc, h.id desc
    limit 10001
  ) rows;

  return jsonb_build_object(
    'row_count', row_count_value,
    'csv', chr(65279) || header_value || E'\r\n'
      || case when body_value = '' then '' else body_value || E'\r\n' end);
end;
$$;

create or replace function public.csv_export(req jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_correlation text;
  correlation_value uuid;
  actor_id uuid;
  input_value jsonb;
  filters_value jsonb;
  dataset_value text;
  audit_dataset_value text := 'invalid';
  payload_value jsonb;
  csv_value text;
  export_id_value uuid := gen_random_uuid();
  generated_at_value timestamptz := clock_timestamp();
  row_count_value integer;
  byte_count_value integer;
  error_code_value text;
  error_message_value text;
  error_details_text text;
begin
  if req is null or jsonb_typeof(req) <> 'object' then
    return private.rpc_error_envelope(
      null, 'business', 'VALIDATION_FAILED', '要求の形式が正しくありません。',
      jsonb_build_object('field', 'request', 'reason', 'invalid_type'));
  end if;
  raw_correlation := req -> 'meta' ->> 'correlation_id';
  correlation_value := private.rpc_try_uuid_v4(raw_correlation);
  if correlation_value is null then
    return private.rpc_error_envelope(
      raw_correlation, 'business', 'VALIDATION_FAILED', 'correlation_id が正しくありません。',
      jsonb_build_object('field', 'meta.correlation_id', 'reason', 'invalid_format'));
  end if;
  actor_id := auth.uid();
  if actor_id is null then
    return private.rpc_error_envelope(
      raw_correlation, 'auth', 'AUTH_REQUIRED', 'ログインが必要です。', null);
  end if;
  if not private.current_user_is_active() then
    return private.rpc_error_envelope(
      raw_correlation, 'auth', 'AUTH_FORBIDDEN', 'CSVを出力する権限がありません。', null);
  end if;

  input_value := req -> 'input';
  if input_value is null or jsonb_typeof(input_value) <> 'object' then
    insert into public.csv_export_audits (
      export_id, correlation_id, exported_by, dataset, filters, generated_at, result_code
    ) values (
      export_id_value, correlation_value, actor_id, 'invalid', '{}'::jsonb,
      generated_at_value, 'VALIDATION_FAILED');
    return private.rpc_error_envelope(
      raw_correlation, 'business', 'VALIDATION_FAILED', 'input が正しくありません。',
      jsonb_build_object('field', 'input', 'reason', 'invalid_type'));
  end if;

  begin
    perform private.csv_validate_filter_keys(input_value, array['dataset', 'filters']);
    dataset_value := private.rpc_input_text(input_value, 'dataset', true);
    if dataset_value not in ('inventory', 'masters', 'history') then
      perform private.rpc_fail(
        'KW400', 'VALIDATION_FAILED', '出力対象が正しくありません。',
        jsonb_build_object('field', 'dataset', 'reason', 'invalid_value'));
    end if;
    audit_dataset_value := dataset_value;
    filters_value := coalesce(input_value -> 'filters', '{}'::jsonb);
    if jsonb_typeof(filters_value) <> 'object' then
      perform private.rpc_fail(
        'KW400', 'VALIDATION_FAILED', 'filters の形式が正しくありません。',
        jsonb_build_object('field', 'filters', 'reason', 'invalid_type'));
    end if;
    if dataset_value = 'history' and not private.current_user_has_role('administrator') then
      return private.rpc_error_envelope(
        raw_correlation, 'auth', 'AUTH_FORBIDDEN', '変更履歴の出力は管理者だけが行えます。', null);
    end if;

    payload_value := case dataset_value
      when 'inventory' then private.csv_inventory_payload(filters_value)
      when 'masters' then private.csv_master_payload(filters_value)
      else private.csv_history_payload(filters_value)
    end;
    row_count_value := (payload_value ->> 'row_count')::integer;
    csv_value := payload_value ->> 'csv';
    byte_count_value := octet_length(csv_value);
    if row_count_value > 10000 or byte_count_value > 10485760 then
      insert into public.csv_export_audits (
        export_id, correlation_id, exported_by, dataset, filters, generated_at,
        row_count, byte_count, result_code
      ) values (
        export_id_value, correlation_value, actor_id, dataset_value, filters_value,
        generated_at_value, row_count_value, byte_count_value, 'EXPORT_LIMIT_EXCEEDED');
      return private.rpc_error_envelope(
        raw_correlation, 'business', 'EXPORT_LIMIT_EXCEEDED',
        '出力上限を超えています。条件を絞って再試行してください。',
        jsonb_build_object('max_rows', 10000, 'max_bytes', 10485760));
    end if;

    insert into public.csv_export_audits (
      export_id, correlation_id, exported_by, dataset, filters, generated_at,
      row_count, byte_count, result_code
    ) values (
      export_id_value, correlation_value, actor_id, dataset_value, filters_value,
      generated_at_value, row_count_value, byte_count_value, 'SUCCESS');
    return jsonb_build_object(
      'ok', true,
      'correlation_id', raw_correlation,
      'data', jsonb_build_object(
        'export_id', export_id_value,
        'filename', dataset_value || '_' ||
          to_char(generated_at_value at time zone 'UTC', 'YYYYMMDD"T"HH24MISS') || '_' ||
          left(replace(export_id_value::text, '-', ''), 8) || '.csv',
        'row_count', row_count_value,
        'csv', csv_value,
        'generated_at', generated_at_value));
  exception
    when sqlstate 'KW400' then
      get stacked diagnostics
        error_code_value = message_text,
        error_message_value = pg_exception_hint,
        error_details_text = pg_exception_detail;
      insert into public.csv_export_audits (
        export_id, correlation_id, exported_by, dataset, filters, generated_at, result_code
      ) values (
        export_id_value, correlation_value, actor_id, audit_dataset_value,
        case when jsonb_typeof(filters_value) = 'object' then filters_value else '{}'::jsonb end,
        generated_at_value, 'VALIDATION_FAILED');
      return private.rpc_error_envelope(
        raw_correlation, 'business', error_code_value, error_message_value,
        nullif(error_details_text, '')::jsonb);
  end;
end;
$$;

revoke all on function private.csv_validate_filter_keys(jsonb, text[]) from public, anon, authenticated;
revoke all on function private.csv_cell(text, boolean) from public, anon, authenticated;
revoke all on function private.csv_timestamp_jst(timestamptz) from public, anon, authenticated;
revoke all on function private.csv_inventory_payload(jsonb) from public, anon, authenticated;
revoke all on function private.csv_master_search_text(text, jsonb) from public, anon, authenticated;
revoke all on function private.csv_master_header(text) from public, anon, authenticated;
revoke all on function private.csv_master_row(text, jsonb) from public, anon, authenticated;
revoke all on function private.csv_master_payload(jsonb) from public, anon, authenticated;
revoke all on function private.csv_history_payload(jsonb) from public, anon, authenticated;

revoke all on function public.csv_export(jsonb) from public, anon;
grant execute on function public.csv_export(jsonb) to authenticated, service_role;

comment on table public.csv_export_audits is
  'Append-only metadata for generated or rejected CSV exports; CSV bodies are not retained.';
comment on function public.csv_export(jsonb) is
  'Exports filtered stage 1 inventory, master, or administrator-only history data as UTF-8 BOM CSV.';

commit;
