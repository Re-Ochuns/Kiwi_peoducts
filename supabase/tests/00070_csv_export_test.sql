begin;

select no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'csv-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"CSV Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'csv-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"CSV Member"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'csv-admin@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"CSV Admin"}', now(), now());

select private.set_user_access('70000000-0000-0000-0000-000000000002', 'active', array['member']);
select private.set_user_access('70000000-0000-0000-0000-000000000003', 'active', array['administrator']);

insert into public.varieties (id, code, name) values
  ('71000000-0000-0000-0000-000000000001', 'CSV-VAR', '=SUM(1,1)'),
  ('71000000-0000-0000-0000-000000000010', 'CSV-PERCENT', 'CSV 100% fruit');
insert into public.orchards (id, code, name) values
  ('71000000-0000-0000-0000-000000000002', 'CSV-ORCHARD', 'CSV農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('71000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000002', 'CSV-PLOT', 'CSV区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('71000000-0000-0000-0000-000000000004', '71000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000001', 'CSV-TREE', 'CSV樹体');
insert into public.suppliers (id, management_code, name) values
  ('71000000-0000-0000-0000-000000000005', 'CSV-SUPPLIER', 'CSV仕入先');
insert into public.workers (id, code, display_name) values
  ('71000000-0000-0000-0000-000000000006', 'CSV-WORKER', 'CSV作業者');
insert into public.storage_locations (id, code, name, location_type) values
  ('71000000-0000-0000-0000-000000000007', 'CSV-COLD', E'CSV "第一"\n冷蔵庫', 'cold_storage');
insert into public.sorting_deadline_rules (
  id, harvest_year, harvest_month, variety_id, deadline_days
) values (
  '71000000-0000-0000-0000-000000000008', 2026, 9,
  '71000000-0000-0000-0000-000000000001', 30
);

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id,
  origin_name, variety_id, total_weight_kg, container_count, sorting_due_on, received_by
) values (
  '72000000-0000-0000-0000-000000000001', 'CSV-RECEIVING-001', 'harvest', '2026-09-01',
  '71000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000003',
  '71000000-0000-0000-0000-000000000004', 'CSV農園',
  '71000000-0000-0000-0000-000000000001', 10.00, 1, '2026-10-01',
  '71000000-0000-0000-0000-000000000006'
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
) values (
  '72000000-0000-0000-0000-000000000002', 'CSV-SORTING-001',
  '72000000-0000-0000-0000-000000000001', '2026-09-02',
  '71000000-0000-0000-0000-000000000006', 10.00, 9.00, 1.00
);
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, reserved_weight_kg, status, location_id
)
select
  '72000000-0000-0000-0000-000000000003', 'CSV-INV-001',
  '72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001',
  id, 9.00, 8.50, 1.25, 'cold_storage', '71000000-0000-0000-0000-000000000007'
from public.grades where code = 'M';

insert into public.change_history (
  id, entity_type, entity_id, operation, before_data, after_data,
  reason, changed_at, changed_by, correlation_id
) values (
  '72000000-0000-0000-0000-000000000004', 'container',
  '72000000-0000-0000-0000-000000000003', 'correct', '{"weight":9}', '{"weight":8.5}',
  'CSV棚卸し', '2026-09-11T15:30:00Z', '70000000-0000-0000-0000-000000000003',
  '74000000-0000-4000-8000-000000000001'
);

create function public.test_csv_req(corr_value text, input_value jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'meta', jsonb_build_object('correlation_id', corr_value),
    'input', input_value
  );
$$;

select has_table('public', 'csv_export_audits', 'csv export audit table exists');
select has_function('public'::name, 'csv_export'::name, array['jsonb']::name[], 'csv_export exists');
select is_definer('public'::name, 'csv_export'::name, array['jsonb']::name[], 'csv_export runs as definer');

set local role anon;
select throws_ok(
  $$select public.csv_export('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute csv_export'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('test.csv_auth', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000010',
  jsonb_build_object('dataset', 'inventory', 'filters', '{}'::jsonb)))::text, true);
select is(current_setting('test.csv_auth')::jsonb -> 'error' ->> 'code', 'AUTH_REQUIRED', 'missing session is rejected');

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select set_config('test.csv_pending', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000011',
  jsonb_build_object('dataset', 'inventory', 'filters', '{}'::jsonb)))::text, true);
select is(current_setting('test.csv_pending')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'pending user is rejected');

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);
select set_config('test.csv_inventory', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000012',
  jsonb_build_object(
    'dataset', 'inventory',
    'filters', jsonb_build_object('search', 'CSV-INV-%', 'status', 'cold_storage', 'sort', 'display_id_asc'))))::text, true);
select is(current_setting('test.csv_inventory')::jsonb ->> 'ok', 'true', 'active member exports inventory');
select is(current_setting('test.csv_inventory')::jsonb -> 'data' ->> 'row_count', '1', 'inventory filters select one row');
select is(
  encode(substring(convert_to(current_setting('test.csv_inventory')::jsonb -> 'data' ->> 'csv', 'UTF8') from 1 for 3), 'hex'),
  'efbbbf', 'CSV bytes start with one UTF-8 BOM');
select ok(
  (current_setting('test.csv_inventory')::jsonb -> 'data' ->> 'csv') like E'%"CSV ""第一""\n冷蔵庫"%',
  'quotes and embedded newlines are preserved and escaped');
select ok(
  position('"''=SUM(1,1)"' in current_setting('test.csv_inventory')::jsonb -> 'data' ->> 'csv') > 0,
  'formula-like text is prefixed with an apostrophe');
select matches(
  current_setting('test.csv_inventory')::jsonb -> 'data' ->> 'filename',
  '^inventory_[0-9]{8}T[0-9]{6}_[0-9a-f]{8}\.csv$', 'server filename is safe and deterministic');

select set_config('test.csv_empty', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000013',
  jsonb_build_object(
    'dataset', 'inventory',
    'filters', jsonb_build_object('search', 'CSV-NOT-FOUND', 'sort', 'updated_desc'))))::text, true);
select is(current_setting('test.csv_empty')::jsonb -> 'data' ->> 'row_count', '0', 'empty export succeeds with zero rows');
select is(
  length(regexp_replace(current_setting('test.csv_empty')::jsonb -> 'data' ->> 'csv', E'[^\n]', '', 'g')),
  1, 'empty export contains only one header line');

select set_config('test.csv_master_literal', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000014',
  jsonb_build_object(
    'dataset', 'masters',
    'filters', jsonb_build_object('master_type', 'variety', 'search', '%', 'active', 'active'))))::text, true);
select is(current_setting('test.csv_master_literal')::jsonb ->> 'ok', 'true', 'member exports masters');
select is(current_setting('test.csv_master_literal')::jsonb -> 'data' ->> 'row_count', '1', 'master percent search is literal');

select set_config('test.csv_master_orchard', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000141',
  jsonb_build_object(
    'dataset', 'masters',
    'filters', jsonb_build_object('master_type', 'orchard', 'search', 'CSV農園', 'active', 'all'))))::text, true);
select is(current_setting('test.csv_master_orchard')::jsonb ->> 'ok', 'true', 'member exports orchards');
select is(current_setting('test.csv_master_orchard')::jsonb -> 'data' ->> 'row_count', '1', 'orchard export selects one row');
select ok(
  (current_setting('test.csv_master_orchard')::jsonb -> 'data' ->> 'csv') like
    chr(65279) || '"内部ID","コード","農園名","有効","バージョン","更新日時JST"' || E'\r\n%CSV農園%',
  'orchard export has a header and body');

select set_config('test.csv_master_hidden_id', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000142',
  jsonb_build_object(
    'dataset', 'masters',
    'filters', jsonb_build_object(
      'master_type', 'variety',
      'search', '71000000-0000-0000-0000-000000000001',
      'active', 'all'))))::text, true);
select is(
  current_setting('test.csv_master_hidden_id')::jsonb -> 'data' ->> 'row_count',
  '0', 'master search excludes fields hidden from the page search');

select set_config('test.csv_master_related', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000015',
  jsonb_build_object(
    'dataset', 'masters',
    'filters', jsonb_build_object('master_type', 'orchard_plot', 'search', 'CSV農園', 'active', 'all'))))::text, true);
select is(current_setting('test.csv_master_related')::jsonb -> 'data' ->> 'row_count', '1', 'master search includes related labels');

select set_config('test.csv_master_unrelated', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000151',
  jsonb_build_object(
    'dataset', 'masters',
    'filters', jsonb_build_object('master_type', 'tree', 'search', 'CSV-ORCHARD', 'active', 'all'))))::text, true);
select is(
  current_setting('test.csv_master_unrelated')::jsonb -> 'data' ->> 'row_count',
  '0', 'tree search excludes orchard labels not searched by the page');

reset role;
select ok(
  position('冷蔵庫' in private.csv_master_search_text(
    'storage_location',
    '{"code":"CSV-COLD","name":"CSV保管場所","location_type":"cold_storage"}'::jsonb)) > 0,
  'storage location search includes the Japanese type label');

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);

select set_config('test.csv_history_member', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000016',
  jsonb_build_object('dataset', 'history', 'filters', '{}'::jsonb)))::text, true);
select is(current_setting('test.csv_history_member')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'member cannot export history');
select is((select count(*) from public.csv_export_audits), 0::bigint, 'member cannot read export audits');
select throws_ok(
  $$insert into public.csv_export_audits (
      export_id, correlation_id, exported_by, dataset, result_code
    ) values (
      gen_random_uuid(), gen_random_uuid(), '70000000-0000-0000-0000-000000000002',
      'inventory', 'SUCCESS')$$,
  '42501', null, 'clients cannot insert export audits'
);

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000003', true);
select set_config('test.csv_history', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000017',
  jsonb_build_object(
    'dataset', 'history',
    'filters', jsonb_build_object(
      'entity_type', 'container',
      'entity_id', '72000000-0000-0000-0000-000000000003',
      'from_date', '2026-09-12', 'to_date', '2026-09-12'))))::text, true);
select is(current_setting('test.csv_history')::jsonb ->> 'ok', 'true', 'administrator exports history');
select is(current_setting('test.csv_history')::jsonb -> 'data' ->> 'row_count', '1', 'history uses inclusive JST date bounds');
select ok(
  (current_setting('test.csv_history')::jsonb -> 'data' ->> 'csv') like '%CSV棚卸し%',
  'history CSV contains the selected audit');

select set_config('test.csv_invalid', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000018',
  jsonb_build_object(
    'dataset', 'inventory',
    'filters', jsonb_build_object('unknown', 'value'))))::text, true);
select is(current_setting('test.csv_invalid')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'unknown filters are rejected');
select is(
  (select count(*) from public.csv_export_audits
   where correlation_id = '74000000-0000-4000-8000-000000000018'
     and result_code = 'VALIDATION_FAILED'),
  1::bigint, 'validation failure is audited');

select throws_ok(
  $$update public.csv_export_audits set result_code = 'SUCCESS'
    where correlation_id = '74000000-0000-4000-8000-000000000018'$$,
  '42501', null, 'clients cannot update export audits'
);

reset role;

set local role service_role;
select throws_ok(
  $$update public.csv_export_audits set result_code = 'SUCCESS'
    where correlation_id = '74000000-0000-4000-8000-000000000018'$$,
  '23514', 'change history is append-only', 'export audit is append-only'
);
reset role;

insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, status
)
select
  gen_random_uuid(), 'CSV-LIMIT-' || lpad(series::text, 5, '0'),
  '72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001',
  g.id, 1.00, 1.00, 'awaiting_label'
from generate_series(1, 10001) series
cross join lateral (select id from public.grades where code = 'M') g;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000003', true);
select set_config('test.csv_row_limit', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000019',
  jsonb_build_object(
    'dataset', 'inventory',
    'filters', jsonb_build_object('search', 'CSV-LIMIT-', 'sort', 'display_id_asc'))))::text, true);
select is(current_setting('test.csv_row_limit')::jsonb -> 'error' ->> 'code', 'EXPORT_LIMIT_EXCEEDED', 'more than 10000 rows are rejected without truncation');
reset role;

delete from public.containers where display_id like 'CSV-LIMIT-%';
insert into public.storage_locations (id, code, name, location_type) values
  ('71000000-0000-0000-0000-000000000009', 'CSV-LARGE', repeat('あ', 4000), 'cold_storage');
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, status, location_id
)
select
  gen_random_uuid(), 'CSV-SIZE-' || lpad(series::text, 4, '0'),
  '72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001',
  g.id, 1.00, 1.00, 'awaiting_label', '71000000-0000-0000-0000-000000000009'
from generate_series(1, 900) series
cross join lateral (select id from public.grades where code = 'M') g;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000003', true);
select set_config('test.csv_size_limit', public.csv_export(public.test_csv_req(
  '74000000-0000-4000-8000-000000000020',
  jsonb_build_object(
    'dataset', 'inventory',
    'filters', jsonb_build_object('search', 'CSV-SIZE-', 'sort', 'display_id_asc'))))::text, true);
select is(current_setting('test.csv_size_limit')::jsonb -> 'error' ->> 'code', 'EXPORT_LIMIT_EXCEEDED', 'CSV larger than 10 MiB is rejected');
select ok(
  (select byte_count from public.csv_export_audits
   where correlation_id = '74000000-0000-4000-8000-000000000020') > 10485760,
  'size rejection records the generated byte count');
reset role;

select * from finish();
rollback;
