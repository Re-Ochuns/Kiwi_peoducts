begin;

select no_plan();

-- Fixtures --------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'sort-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Sort Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'sort-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Sort Member"}', now(), now());

select private.set_user_access('50000000-0000-0000-0000-000000000002', 'active', array['member']);

insert into public.varieties (id, code, name) values
  ('51000000-0000-0000-0000-000000000001', 'SORT-HW', '選果テストヘイワード');
insert into public.orchards (id, code, name) values
  ('52000000-0000-0000-0000-000000000001', 'SORT-ORCHARD', '選果テスト農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('53000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'SORT-PLOT', '選果テスト区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('54000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', 'SORT-TREE', '選果テスト樹');
insert into public.workers (id, code, display_name) values
  ('55000000-0000-0000-0000-000000000001', 'SORT-WORKER', '選果テスト作業者');

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values
  ('56000000-0000-0000-0000-000000000001', '受入-2029-TEST-001', 'harvest', '2029-05-01',
   '52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001',
   '54000000-0000-0000-0000-000000000001', '選果テスト農園', '51000000-0000-0000-0000-000000000001',
   10.00, 2, '2029-05-31', '55000000-0000-0000-0000-000000000001'),
  ('56000000-0000-0000-0000-000000000002', '受入-2029-TEST-002', 'harvest', '2029-05-02',
   '52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001',
   '54000000-0000-0000-0000-000000000001', '選果テスト農園', '51000000-0000-0000-0000-000000000001',
   5.00, 1, '2029-05-31', '55000000-0000-0000-0000-000000000001'),
  ('56000000-0000-0000-0000-000000000003', '受入-2029-TEST-003', 'harvest', '2029-05-03',
   '52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001',
   '54000000-0000-0000-0000-000000000001', '選果テスト農園', '51000000-0000-0000-0000-000000000001',
   8.00, 1, '2029-05-31', '55000000-0000-0000-0000-000000000001');

-- Request helpers (rolled back with the test transaction).

create function public.test_sorting_req(key_value text, corr_value text, input_value jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', key_value, 'correlation_id', corr_value),
    'input', input_value
  );
$$;

create function public.test_sorting_input(lot_value text, version_value integer, containers_value jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'receiving_lot_id', lot_value,
    'sorting_date', '2029-05-10',
    'worker_id', '55000000-0000-0000-0000-000000000001',
    'expected_lot_version', version_value,
    'containers', containers_value
  );
$$;

-- Function definitions --------------------------------------------------------

select has_function('public'::name, 'sorting_confirm'::name, array['jsonb']::name[], 'sorting_confirm exists');
select is_definer('public'::name, 'sorting_confirm'::name, array['jsonb']::name[], 'sorting_confirm runs as definer');

-- Auth boundaries -------------------------------------------------------------

set local role anon;
select throws_ok(
  $$select public.sorting_confirm('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute sorting_confirm'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config('test.sort_forbidden',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000090', '5c000000-0000-4000-8000-000000000090',
    public.test_sorting_input('56000000-0000-0000-0000-000000000001', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":6.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_forbidden')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'pending user cannot confirm sorting');

-- Happy path -------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
select set_config('test.sort1',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000001', '5c000000-0000-4000-8000-000000000001',
    public.test_sorting_input('56000000-0000-0000-0000-000000000001', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":6.00},{"grade_id":"a2000000-0000-0000-0000-000000000004","weight_kg":3.50}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort1')::jsonb ->> 'ok', 'true', 'member confirms whole-lot sorting');
select is(current_setting('test.sort1')::jsonb -> 'data' ->> 'display_id', '選果-2029-001', 'sorting display id is numbered per year');
select is(current_setting('test.sort1')::jsonb -> 'data' ->> 'input_weight_kg', '10.00', 'input weight comes from the lot');
select is(current_setting('test.sort1')::jsonb -> 'data' ->> 'output_weight_kg', '9.50', 'output weight is the container total');
select is(current_setting('test.sort1')::jsonb -> 'data' ->> 'loss_weight_kg', '0.50', 'loss is derived from the difference');
select is(current_setting('test.sort1')::jsonb -> 'data' ->> 'receiving_lot_status', 'sorted', 'lot is closed');
select is(current_setting('test.sort1')::jsonb -> 'data' ->> 'receiving_lot_version', '2', 'lot version is incremented');
select is(current_setting('test.sort1')::jsonb -> 'data' -> 'containers' -> 0 ->> 'display_id', '選果-2029-001-1', 'first container gets branch number 1');
select is(current_setting('test.sort1')::jsonb -> 'data' -> 'containers' -> 1 ->> 'display_id', '選果-2029-001-2', 'second container gets branch number 2');
select is(current_setting('test.sort1')::jsonb -> 'data' -> 'containers' -> 0 ->> 'status', 'awaiting_label', 'containers await labeling');

-- Idempotent replay and key reuse ----------------------------------------------

select set_config('test.sort1_replay',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000001', '5c000000-0000-4000-8000-000000000002',
    public.test_sorting_input('56000000-0000-0000-0000-000000000001', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":6.00},{"grade_id":"a2000000-0000-0000-0000-000000000004","weight_kg":3.50}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort1_replay')::jsonb ->> 'ok', 'true', 'resend succeeds');
select is(current_setting('test.sort1_replay')::jsonb ->> 'idempotent_replay', 'true', 'resend is a replay');
select is(current_setting('test.sort1_replay')::jsonb -> 'data' ->> 'display_id', '選果-2029-001', 'replay returns the stored sorting result');

select set_config('test.sort1_reuse',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000001', '5c000000-0000-4000-8000-000000000003',
    public.test_sorting_input('56000000-0000-0000-0000-000000000001', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":6.50},{"grade_id":"a2000000-0000-0000-0000-000000000004","weight_kg":3.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort1_reuse')::jsonb -> 'error' ->> 'code', 'IDEMPOTENCY_KEY_REUSED', 'same key with different containers is rejected');

-- Double confirmation ------------------------------------------------------------

select set_config('test.sort1_again',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000002', '5c000000-0000-4000-8000-000000000004',
    public.test_sorting_input('56000000-0000-0000-0000-000000000001', 2,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":6.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort1_again')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'sorted lot cannot be confirmed twice');
select is(current_setting('test.sort1_again')::jsonb -> 'error' -> 'details' -> 'current' ->> 'status', 'sorted', 'conflict reports the sorted status');

-- Weight consistency --------------------------------------------------------------

select set_config('test.sort2_exceeded',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000003', '5c000000-0000-4000-8000-000000000005',
    public.test_sorting_input('56000000-0000-0000-0000-000000000002', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":5.01}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort2_exceeded')::jsonb -> 'error' ->> 'code', 'SORTING_WEIGHT_EXCEEDED', 'container total above the lot weight is rejected');
select is(current_setting('test.sort2_exceeded')::jsonb -> 'error' ->> 'category', 'business', 'weight excess is a business error');
select is(current_setting('test.sort2_exceeded')::jsonb -> 'error' -> 'details' ->> 'input_total_kg', '5.01', 'details carry the container total');
select is(current_setting('test.sort2_exceeded')::jsonb -> 'error' -> 'details' ->> 'lot_total_kg', '5.00', 'details carry the lot total');

select set_config('test.sort2',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000004', '5c000000-0000-4000-8000-000000000006',
    public.test_sorting_input('56000000-0000-0000-0000-000000000002', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":4.80}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort2')::jsonb ->> 'ok', 'true', 'corrected weights confirm with a fresh key');
select is(current_setting('test.sort2')::jsonb -> 'data' ->> 'display_id', '選果-2029-002', 'failed attempts do not burn display ids');
select is(current_setting('test.sort2')::jsonb -> 'data' ->> 'loss_weight_kg', '0.20', 'remaining weight is recorded as loss');

-- Optimistic locking ---------------------------------------------------------------

select set_config('test.sort3_stale',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000005', '5c000000-0000-4000-8000-000000000007',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 2,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":7.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort3_stale')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'stale lot version is a conflict');
select is(current_setting('test.sort3_stale')::jsonb -> 'error' -> 'details' -> 'current' ->> 'version', '1', 'conflict reports the current lot version');

-- Container element validation ------------------------------------------------------

select set_config('test.sort_empty',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000006', '5c000000-0000-4000-8000-000000000008',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1, '[]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_empty')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'empty container list is rejected');
select is(current_setting('test.sort_empty')::jsonb -> 'error' -> 'details' ->> 'field', 'containers', 'empty list names the containers field');
select is(current_setting('test.sort_empty')::jsonb -> 'error' -> 'details' ->> 'reason', 'required', 'an empty container list is a required violation');

-- Missing / null / non-array containers follow receiving_register section 5.
select set_config('test.sort_missing',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000060', '5c000000-0000-4000-8000-000000000060',
    jsonb_build_object(
      'receiving_lot_id', '56000000-0000-0000-0000-000000000003',
      'sorting_date', '2029-05-10',
      'worker_id', '55000000-0000-0000-0000-000000000001',
      'expected_lot_version', 1)))::text,
  true);
select is(current_setting('test.sort_missing')::jsonb -> 'error' -> 'details' ->> 'reason', 'required', 'a missing container list is a required violation');

select set_config('test.sort_null',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000061', '5c000000-0000-4000-8000-000000000061',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1, 'null'::jsonb)))::text,
  true);
select is(current_setting('test.sort_null')::jsonb -> 'error' -> 'details' ->> 'reason', 'required', 'a null container list is a required violation');

select set_config('test.sort_object',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000062', '5c000000-0000-4000-8000-000000000062',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1, '{}'::jsonb)))::text,
  true);
select is(current_setting('test.sort_object')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'a non-array container value is rejected');
select is(current_setting('test.sort_object')::jsonb -> 'error' -> 'details' ->> 'field', 'containers', 'non-array names the containers field');
select is(current_setting('test.sort_object')::jsonb -> 'error' -> 'details' ->> 'reason', 'invalid_type', 'an object container value is an invalid type');

select set_config('test.sort_scalar',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000063', '5c000000-0000-4000-8000-000000000063',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1, '5'::jsonb)))::text,
  true);
select is(current_setting('test.sort_scalar')::jsonb -> 'error' -> 'details' ->> 'reason', 'invalid_type', 'a scalar container value is an invalid type');

-- Envelope keys must be UUID v4 (common contract section 3), like the receiving RPCs.
select set_config('test.sort_key_v1',
  public.sorting_confirm(jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', '9f4c1e5a-7b2d-1c8e-9a31-5d2f8c6b1a90', 'correlation_id', '5c000000-0000-4000-8000-000000000070'),
    'input', public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":1.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_key_v1')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'a version 1 idempotency key is rejected');
select is(current_setting('test.sort_key_v1')::jsonb -> 'error' -> 'details' ->> 'field', 'meta.idempotency_key', 'non-v4 key names the idempotency field');
select is(current_setting('test.sort_key_v1')::jsonb -> 'error' -> 'details' ->> 'reason', 'invalid_format', 'non-v4 key is an invalid format');

select set_config('test.sort_key_nil',
  public.sorting_confirm(jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', '00000000-0000-0000-0000-000000000000', 'correlation_id', '5c000000-0000-4000-8000-000000000071'),
    'input', public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":1.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_key_nil')::jsonb -> 'error' -> 'details' ->> 'field', 'meta.idempotency_key', 'the nil uuid is not a valid v4 key');

select set_config('test.sort_corr_v1',
  public.sorting_confirm(jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', '59000000-0000-4000-8000-000000000072', 'correlation_id', '9f4c1e5a-7b2d-1c8e-9a31-5d2f8c6b1a90'),
    'input', public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":1.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_corr_v1')::jsonb -> 'error' -> 'details' ->> 'field', 'meta.correlation_id', 'a non-v4 correlation id is rejected');

select set_config('test.sort_precision',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000007', '5c000000-0000-4000-8000-000000000009',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":1.234}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_precision')::jsonb -> 'error' -> 'details' ->> 'field', 'containers[0].weight_kg', 'element failures carry the array index');
select is(current_setting('test.sort_precision')::jsonb -> 'error' -> 'details' ->> 'reason', 'invalid_precision', 'precision failures keep the reason');

select set_config('test.sort_grade',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000008', '5c000000-0000-4000-8000-000000000010',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":1.00},{"grade_id":"5f000000-0000-4000-8000-000000000000","weight_kg":1.00}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_grade')::jsonb -> 'error' -> 'details' ->> 'field', 'containers[1].grade_id', 'unknown grade names the indexed field');

select set_config('test.sort_zero',
  public.sorting_confirm(public.test_sorting_req('59000000-0000-4000-8000-000000000009', '5c000000-0000-4000-8000-000000000011',
    public.test_sorting_input('56000000-0000-0000-0000-000000000003', 1,
      '[{"grade_id":"a2000000-0000-0000-0000-000000000005","weight_kg":0}]'::jsonb)))::text,
  true);
select is(current_setting('test.sort_zero')::jsonb -> 'error' -> 'details' ->> 'reason', 'out_of_range', 'zero-weight container is rejected');

-- Persisted state and audit records --------------------------------------------------

reset role;
select is(
  (select status from public.receiving_lots where id = '56000000-0000-0000-0000-000000000001'),
  'sorted', 'confirmed lot is closed');
select is(
  (select version from public.receiving_lots where id = '56000000-0000-0000-0000-000000000001'),
  2::bigint, 'confirmed lot version is incremented');
select is(
  (select count(*) from public.sorting_results where receiving_lot_id = '56000000-0000-0000-0000-000000000001'),
  1::bigint, 'replay creates no second sorting result');
select is(
  (select loss_weight_kg::text from public.sorting_results where receiving_lot_id = '56000000-0000-0000-0000-000000000001'),
  '0.50', 'loss weight is persisted');
select is(
  (select count(*) from public.containers c
    join public.sorting_results s on s.id = c.sorting_result_id
    where s.receiving_lot_id = '56000000-0000-0000-0000-000000000001'),
  2::bigint, 'exactly the requested containers are created');
select is(
  (select count(*) from public.containers c
    join public.sorting_results s on s.id = c.sorting_result_id
    where s.receiving_lot_id = '56000000-0000-0000-0000-000000000001'
      and c.variety_id = '51000000-0000-0000-0000-000000000001'
      and c.current_weight_kg = c.original_weight_kg
      and c.status = 'awaiting_label'),
  2::bigint, 'containers inherit the variety and start with full stock');
select is(
  (select count(*) from public.label_jobs j
    join public.containers c on c.id = j.container_id
    join public.sorting_results s on s.id = c.sorting_result_id
    where s.receiving_lot_id = '56000000-0000-0000-0000-000000000001'
      and j.status = 'not_printed'),
  2::bigint, 'each container gets an unprinted label job');
select is(
  (select count(*) from public.change_history
    where correlation_id = '5c000000-0000-4000-8000-000000000001'),
  6::bigint, 'confirmation writes six audit rows');
select is(
  (select count(*) from public.change_history
    where correlation_id = '5c000000-0000-4000-8000-000000000001'
      and entity_type = 'receiving_lot' and operation = 'transition'
      and before_data ->> 'status' = 'awaiting_sorting'
      and after_data ->> 'status' = 'sorted'),
  1::bigint, 'lot transition is recorded with before and after images');
select is(
  (select status from public.receiving_lots where id = '56000000-0000-0000-0000-000000000002'),
  'sorted', 'second lot confirmed after the failed attempt');
select is(
  (select count(*) from public.sorting_results where receiving_lot_id = '56000000-0000-0000-0000-000000000003'),
  0::bigint, 'failed confirmations leave no sorting result');
select is(
  (select status from public.receiving_lots where id = '56000000-0000-0000-0000-000000000003'),
  'awaiting_sorting', 'failed confirmations leave the lot open');
select is(
  (select r.response ->> 'ok' from private.idempotency_records r
    where r.idempotency_key = '59000000-0000-4000-8000-000000000001'),
  'true', 'success envelope is stored for replay');

select * from finish();
rollback;
