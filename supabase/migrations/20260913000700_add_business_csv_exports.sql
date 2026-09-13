begin;
alter table public.csv_export_audits drop constraint csv_export_audits_dataset_check;
alter table public.csv_export_audits add constraint csv_export_audits_dataset_check
  check (dataset in ('inventory','masters','history','invalid','orders','ripening','shipments'));

create function private.csv_business_filters(dataset_value text, filters_value jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare search_value text; status_value text; from_value date; to_value date; order_value uuid;
begin
  perform private.csv_validate_filter_keys(filters_value,case when dataset_value='shipments'
    then array['search','status','from_date','to_date','order_id']
    else array['search','status','from_date','to_date'] end);
  search_value:=coalesce(private.rpc_input_text(filters_value,'search',false),'');
  status_value:=coalesce(private.rpc_input_text(filters_value,'status',false),'all');
  from_value:=private.rpc_input_date(filters_value,'from_date',false);
  to_value:=private.rpc_input_date(filters_value,'to_date',false);
  if dataset_value='shipments' then order_value:=private.rpc_input_uuid(filters_value,'order_id',false); end if;
  if length(search_value)>100 or (from_value is not null and to_value is not null and from_value>to_value)
    or not (status_value=any(case dataset_value
      when 'orders' then array['all','active','draft','confirmed','in_progress','partially_shipped','shipped','cancelled']
      when 'ripening' then array['all','draft','confirmed','in_progress','completed','cancelled']
      when 'shipments' then array['all','confirmed','cancelled'] else array[]::text[] end)) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','出力条件が正しくありません。');
  end if;
  return jsonb_strip_nulls(jsonb_build_object('search',nullif(search_value,''),'status',status_value,
    'from_date',from_value,'to_date',to_value,'order_id',order_value));
end;
$$;

create function private.csv_business_payload(dataset_value text, filters_value jsonb)
returns jsonb language plpgsql volatile set search_path='' as $$
declare search_value text:=lower(coalesce(filters_value->>'search',''));
  status_value text:=filters_value->>'status'; from_value date:=(filters_value->>'from_date')::date;
  to_value date:=(filters_value->>'to_date')::date; order_value uuid:=(filters_value->>'order_id')::uuid;
  header_value text; body_value text; row_count_value integer;
begin
  if dataset_value='orders' then
    header_value := '"受注内部ID","受注番号","顧客内部ID","顧客名","顧客愛称","受注日","出荷予定日","品種","等級","受注重量kg","割当重量kg","出荷済重量kg","状態コード","要再確認","送付先JSON","備考","更新日時JST"';
    select count(*)::integer,coalesce(string_agg(row_text,E'\r\n' order by seq),'') into row_count_value,body_value
    from (select row_number() over(order by o.scheduled_ship_on,o.order_number,o.id) seq, array_to_string(array[
      private.csv_cell(o.id::text),
      private.csv_cell(o.order_number),
      private.csv_cell(o.customer_id::text),
      private.csv_cell(c.name),
      private.csv_cell(c.nickname),
      private.csv_cell(o.ordered_on::text),
      private.csv_cell(o.scheduled_ship_on::text),
      private.csv_cell(v.name),
      private.csv_cell(g.code),
      private.csv_cell(to_char(o.ordered_weight_kg,'FM9999999990.00'), false),
      private.csv_cell(to_char(o.allocated_weight_kg,'FM9999999990.00'), false),
      private.csv_cell(to_char(private.shipped_weight(o.id),'FM9999999990.00'), false),
      private.csv_cell(o.status),
      private.csv_cell(o.needs_review::text),
      private.csv_cell(o.shipping_destination_snapshot::text),
      private.csv_cell(o.notes),
      private.csv_cell(private.csv_timestamp_jst(o.updated_at))
    ],',') row_text from public.orders o join public.customers c on c.id=o.customer_id join public.varieties v on v.id=o.variety_id join public.grades g on g.id=o.grade_id
    where (status_value in ('all','active') or o.status=status_value) and (status_value<>'active' or o.status in ('draft','confirmed','in_progress','partially_shipped'))
      and (search_value='' or position(search_value in lower(concat_ws(' ',o.order_number,c.name,c.nickname)))>0)
      and (from_value is null or o.scheduled_ship_on>=from_value) and (to_value is null or o.scheduled_ship_on<=to_value)
    order by o.scheduled_ship_on,o.order_number,o.id limit 10001) rows;
  elsif dataset_value='ripening' then
    header_value := '"追熟内部ID","追熟ID","収穫年","収穫月","品種","等級","重量kg","用途","状態コード","要再確認","保管場所","担当者","注入予定JST","完了予定JST","抜き計算予定JST","寝かせ終了計算予定JST","出荷可能期限JST","賞味期限JST","条件コピーJSON","注入実績JST","注入実績温度","注入担当者","注入場所","注入備考","抜き確認実績JST","抜き確認実績温度","抜き確認担当者","抜き確認場所","抜き確認備考","追熟確認実績JST","追熟確認実績温度","追熟確認担当者","追熟確認場所","追熟確認備考","寝かせ開始実績JST","寝かせ実績温度","計画備考","更新日時JST"';
    select count(*)::integer,coalesce(string_agg(row_text,E'\r\n' order by seq),'') into row_count_value,body_value
    from (select row_number() over(order by l.planned_ethylene_at,l.display_id,l.id) seq, array_to_string(array[
      private.csv_cell(l.id::text),
      private.csv_cell(l.display_id),
      private.csv_cell(l.harvest_year::text),
      private.csv_cell(l.harvest_month::text),
      private.csv_cell(v.name),
      private.csv_cell(g.code),
      private.csv_cell(to_char(l.total_weight_kg,'FM9999999990.00'), false),
      private.csv_cell(l.use_type),
      private.csv_cell(l.status),
      private.csv_cell(l.needs_review::text),
      private.csv_cell(s.name),
      private.csv_cell(w.display_name),
      private.csv_cell(private.csv_timestamp_jst(l.planned_ethylene_at)),
      private.csv_cell(private.csv_timestamp_jst(l.planned_completion_at)),
      private.csv_cell(private.csv_timestamp_jst(l.calculated_removal_at)),
      private.csv_cell(private.csv_timestamp_jst(l.calculated_rest_end_at)),
      private.csv_cell(private.csv_timestamp_jst(l.calculated_shippable_until)),
      private.csv_cell(private.csv_timestamp_jst(l.calculated_best_before_at)),
      private.csv_cell(l.master_snapshot::text),
      private.csv_cell(private.csv_timestamp_jst(i.actual_at)),
      private.csv_cell(i.actual_temperature::text, false),
      private.csv_cell(iw.display_name),
      private.csv_cell(is_loc.name),
      private.csv_cell(i.notes),
      private.csv_cell(private.csv_timestamp_jst(e.actual_at)),
      private.csv_cell(e.actual_temperature::text, false),
      private.csv_cell(ew.display_name),
      private.csv_cell(es_loc.name),
      private.csv_cell(e.notes),
      private.csv_cell(private.csv_timestamp_jst(p.actual_at)),
      private.csv_cell(p.actual_temperature::text, false),
      private.csv_cell(pw.display_name),
      private.csv_cell(ps_loc.name),
      private.csv_cell(p.notes),
      private.csv_cell(private.csv_timestamp_jst(e.rest_started_at)),
      private.csv_cell(e.rest_temperature::text, false),
      private.csv_cell(l.notes),
      private.csv_cell(private.csv_timestamp_jst(l.updated_at))
    ],',') row_text from public.ripening_lots l join public.varieties v on v.id=l.variety_id join public.grades g on g.id=l.grade_id join public.storage_locations s on s.id=l.storage_location_id join public.workers w on w.id=l.assigned_worker_id
 left join public.ripening_work_results i on i.ripening_lot_id=l.id and i.work_type='ethylene_injection' left join public.workers iw on iw.id=i.performed_by left join public.storage_locations is_loc on is_loc.id=i.location_id
 left join public.ripening_work_results e on e.ripening_lot_id=l.id and e.work_type='ethylene_removal_check' left join public.workers ew on ew.id=e.performed_by left join public.storage_locations es_loc on es_loc.id=e.location_id
 left join public.ripening_work_results p on p.ripening_lot_id=l.id and p.work_type='ripeness_check' left join public.workers pw on pw.id=p.performed_by left join public.storage_locations ps_loc on ps_loc.id=p.location_id
    where (status_value in ('all') or l.status=status_value) and true
      and (search_value='' or position(search_value in lower(concat_ws(' ',l.display_id,v.name,g.code)))>0)
      and (from_value is null or (l.planned_ethylene_at at time zone 'Asia/Tokyo')::date>=from_value) and (to_value is null or (l.planned_ethylene_at at time zone 'Asia/Tokyo')::date<=to_value)
    order by l.planned_ethylene_at,l.display_id,l.id limit 10001) rows;
  elsif dataset_value='shipments' then
    header_value := '"出荷内部ID","出荷ID","明細内部ID","受注内部ID","受注番号","顧客名","顧客コピーJSON","送付先コピーJSON","出荷実績JST","出荷担当者","状態コード","コンテナ内部ID","コンテナID","追熟ID","品種","等級","出荷重量kg","取消日時JST","取消理由","備考"';
    select count(*)::integer,coalesce(string_agg(row_text,E'\r\n' order by seq),'') into row_count_value,body_value
    from (select row_number() over(order by s.shipped_at desc,s.id desc,c.display_id,sl.id) seq, array_to_string(array[
      private.csv_cell(s.id::text),
      private.csv_cell(s.display_id),
      private.csv_cell(sl.id::text),
      private.csv_cell(o.id::text),
      private.csv_cell(o.order_number),
      private.csv_cell(s.customer_snapshot->>'name'),
      private.csv_cell(s.customer_snapshot::text),
      private.csv_cell(s.shipping_destination_snapshot::text),
      private.csv_cell(private.csv_timestamp_jst(s.shipped_at)),
      private.csv_cell(w.display_name),
      private.csv_cell(s.status),
      private.csv_cell(c.id::text),
      private.csv_cell(c.display_id),
      private.csv_cell(l.display_id),
      private.csv_cell(v.name),
      private.csv_cell(g.code),
      private.csv_cell(to_char(sl.shipped_weight_kg,'FM9999999990.00'), false),
      private.csv_cell(private.csv_timestamp_jst(s.cancelled_at)),
      private.csv_cell(s.cancellation_reason),
      private.csv_cell(s.notes)
    ],',') row_text from public.shipments s join public.orders o on o.id=s.order_id join public.shipment_lines sl on sl.shipment_id=s.id join public.containers c on c.id=sl.container_id join public.ripening_lots l on l.id=c.ripening_lot_id join public.varieties v on v.id=c.variety_id join public.grades g on g.id=c.grade_id join public.workers w on w.id=s.shipped_by
    where (status_value in ('all') or s.status=status_value) and (order_value is null or o.id=order_value) and (order_value is not null or o.status in ('confirmed','in_progress','partially_shipped','shipped'))
      and (search_value='' or position(search_value in lower(concat_ws(' ',s.display_id,o.order_number,s.customer_snapshot->>'name',s.customer_snapshot->>'nickname',c.display_id)))>0)
      and (from_value is null or (s.shipped_at at time zone 'Asia/Tokyo')::date>=from_value) and (to_value is null or (s.shipped_at at time zone 'Asia/Tokyo')::date<=to_value)
    order by s.shipped_at desc,s.id desc,c.display_id,sl.id limit 10001) rows;
  else raise exception 'unsupported business CSV dataset'; end if;
  return jsonb_build_object('row_count',row_count_value,'csv',chr(65279)||header_value||E'\r\n'||case when body_value='' then '' else body_value||E'\r\n' end);
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
    if dataset_value not in ('inventory', 'masters', 'history', 'orders', 'ripening', 'shipments') then
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

    if dataset_value in ('orders','ripening','shipments') then
      filters_value := private.csv_business_filters(dataset_value,filters_value);
    end if;
    payload_value := case dataset_value
      when 'inventory' then private.csv_inventory_payload(filters_value)
      when 'masters' then private.csv_master_payload(filters_value)
      when 'history' then private.csv_history_payload(filters_value)
      else private.csv_business_payload(dataset_value, filters_value)
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

revoke all on function private.csv_business_filters(text,jsonb) from public,anon,authenticated;
revoke all on function private.csv_business_payload(text,jsonb) from public,anon,authenticated;
commit;
