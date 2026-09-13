begin;

-- S3-04 review: keep automatic history in exports and support the new master
-- wherever the shared master-type registry is used by the existing CSV API.
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
    when 'ripening_rule' then concat_ws(
      ' ', row_value ->> 'harvest_year', row_value ->> 'harvest_month', row_value ->> 'variety_id',
      row_value ->> 'ethylene_temperature', row_value ->> 'ethylene_hours',
      row_value ->> 'rest_temperature', row_value ->> 'rest_days',
      row_value ->> 'shippable_days', row_value ->> 'best_before_days')
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
  elsif master_type_value in ('sorting_deadline_rule', 'ripening_rule') then
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
    when 'ripening_rule' then '"内部ID","収穫年","収穫月","品種内部ID","エチレン処理温度","エチレン処理時間","寝かせ温度","寝かせ日数","出荷可能日数","賞味期限日数","有効","バージョン","更新日時JST"'
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
    when 'ripening_rule' then array[
      private.csv_cell(row_value ->> 'id', false),
      private.csv_cell(row_value ->> 'harvest_year', false),
      private.csv_cell(row_value ->> 'harvest_month', false),
      private.csv_cell(row_value ->> 'variety_id', false),
      private.csv_cell(row_value ->> 'ethylene_temperature', false),
      private.csv_cell(row_value ->> 'ethylene_hours', false),
      private.csv_cell(row_value ->> 'rest_temperature', false),
      private.csv_cell(row_value ->> 'rest_days', false),
      private.csv_cell(row_value ->> 'shippable_days', false),
      private.csv_cell(row_value ->> 'best_before_days', false)]
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
    when 'ripening_rule' then 't.harvest_year, t.harvest_month, t.variety_id, t.id'
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
        private.csv_cell(case when h.changed_by is null then 'システム（自動更新）' else p.display_name end),
        private.csv_cell(h.correlation_id::text, false)
      ], ',') as row_text
    from public.change_history h
    left join public.profiles p on p.id = h.changed_by
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

commit;
