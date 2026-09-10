begin;

select no_plan();

-- Fixtures --------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rpc-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"RPC Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rpc-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"RPC Member"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'rpc-admin@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"RPC Admin"}', now(), now());

select private.set_user_access('40000000-0000-0000-0000-000000000002', 'active', array['member']);
select private.set_user_access('40000000-0000-0000-0000-000000000003', 'active', array['administrator']);

insert into public.varieties (id, code, name) values
  ('41000000-0000-0000-0000-000000000001', 'RPC-HW', 'RPCテストヘイワード'),
  ('41000000-0000-0000-0000-000000000002', 'RPC-KR', 'RPCテスト香緑');
insert into public.orchards (id, code, name) values
  ('42000000-0000-0000-0000-000000000001', 'RPC-ORCHARD', 'RPCテスト農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('43000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001', 'RPC-PLOT', 'RPCテスト区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000001', 'RPC-TREE-1', 'RPCテスト樹1'),
  ('44000000-0000-0000-0000-000000000002', '43000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000002', 'RPC-TREE-2', 'RPCテスト樹2');
insert into public.suppliers (id, management_code, name) values
  ('45000000-0000-0000-0000-000000000001', 'RPC-SUPPLIER', 'RPCテスト仕入先');
insert into public.workers (id, code, display_name, is_active) values
  ('46000000-0000-0000-0000-000000000001', 'RPC-WORKER-1', 'RPCテスト作業者', true),
  ('46000000-0000-0000-0000-000000000002', 'RPC-WORKER-2', 'RPC無効作業者', false);
insert into public.sorting_deadline_rules (id, harvest_year, harvest_month, variety_id, deadline_days) values
  ('47000000-0000-0000-0000-000000000001', 2028, 5, '41000000-0000-0000-0000-000000000001', 21);

-- Request helpers (rolled back with the test transaction).

create function public.test_receiving_req(key_value text, corr_value text, input_value jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', key_value, 'correlation_id', corr_value),
    'input', input_value
  );
$$;

create function public.test_harvest_input()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'source_type', 'harvest',
    'received_date', '2028-05-01',
    'orchard_id', '42000000-0000-0000-0000-000000000001',
    'plot_id', '43000000-0000-0000-0000-000000000001',
    'tree_id', '44000000-0000-0000-0000-000000000001',
    'origin_name', 'RPCテスト農園 RPCテスト区画',
    'variety_id', '41000000-0000-0000-0000-000000000001',
    'total_weight_kg', 25.50,
    'container_count', 2,
    'worker_id', '46000000-0000-0000-0000-000000000001'
  );
$$;

create function public.test_purchase_input()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'source_type', 'purchase',
    'received_date', '2028-07-01',
    'supplier_id', '45000000-0000-0000-0000-000000000001',
    'supplier_reference', 'PO-2028-001',
    'origin_name', 'RPCテスト仕入産地',
    'variety_id', '41000000-0000-0000-0000-000000000001',
    'total_weight_kg', 12.30,
    'container_count', 1,
    'worker_id', '46000000-0000-0000-0000-000000000001'
  );
$$;

-- Function definitions --------------------------------------------------------

select has_function('public'::name, 'receiving_register'::name, array['jsonb']::name[], 'receiving_register exists');
select has_function('public'::name, 'receiving_correct'::name, array['jsonb']::name[], 'receiving_correct exists');
select is_definer('public'::name, 'receiving_register'::name, array['jsonb']::name[], 'receiving_register runs as definer');
select is_definer('public'::name, 'receiving_correct'::name, array['jsonb']::name[], 'receiving_correct runs as definer');

-- Auth boundaries -------------------------------------------------------------

set local role anon;
select throws_ok(
  $$select public.receiving_register('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute receiving_register'
);
select throws_ok(
  $$select public.receiving_correct('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute receiving_correct'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('test.auth_required',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000090', '4c000000-0000-4000-8000-000000000090', public.test_harvest_input()))::text,
  true);
select is(current_setting('test.auth_required')::jsonb -> 'error' ->> 'code', 'AUTH_REQUIRED', 'missing session is rejected');
select is(current_setting('test.auth_required')::jsonb -> 'error' ->> 'category', 'auth', 'missing session is an auth error');

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('test.auth_forbidden',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000091', '4c000000-0000-4000-8000-000000000091', public.test_harvest_input()))::text,
  true);
select is(current_setting('test.auth_forbidden')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'pending user is rejected');

-- Harvest registration happy path ---------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select set_config('test.reg1',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000001', public.test_harvest_input()))::text,
  true);
select is(current_setting('test.reg1')::jsonb ->> 'ok', 'true', 'member registers a harvest lot');
select is(current_setting('test.reg1')::jsonb ->> 'correlation_id', '4c000000-0000-4000-8000-000000000001', 'correlation id is echoed');
select is(current_setting('test.reg1')::jsonb ->> 'idempotent_replay', 'false', 'first call is not a replay');
select is(current_setting('test.reg1')::jsonb -> 'data' ->> 'display_id', '受入-2028-001', 'display id is numbered per year');
select is(current_setting('test.reg1')::jsonb -> 'data' ->> 'status', 'awaiting_sorting', 'new lot awaits sorting');
select is(current_setting('test.reg1')::jsonb -> 'data' ->> 'version', '1', 'new lot starts at version 1');
select is(current_setting('test.reg1')::jsonb -> 'data' ->> 'sorting_due_date', '2028-05-22', 'sorting due date comes from the deadline rule');

-- Idempotent replay and key reuse ----------------------------------------------

select set_config('test.reg1_replay',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000002', public.test_harvest_input()))::text,
  true);
select is(current_setting('test.reg1_replay')::jsonb ->> 'ok', 'true', 'idempotent resend succeeds');
select is(current_setting('test.reg1_replay')::jsonb ->> 'idempotent_replay', 'true', 'idempotent resend is a replay');
select is(current_setting('test.reg1_replay')::jsonb ->> 'correlation_id', '4c000000-0000-4000-8000-000000000002', 'replay echoes the new correlation id');
select is(current_setting('test.reg1_replay')::jsonb -> 'data' ->> 'display_id', '受入-2028-001', 'replay returns the stored result');

select set_config('test.reg1_reuse',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000003', public.test_harvest_input() || jsonb_build_object('total_weight_kg', 26.00)))::text,
  true);
select is(current_setting('test.reg1_reuse')::jsonb -> 'error' ->> 'code', 'IDEMPOTENCY_KEY_REUSED', 'same key with different input is rejected');
select is(current_setting('test.reg1_reuse')::jsonb -> 'error' ->> 'category', 'conflict', 'key reuse is a conflict');

-- Purchase registration and administrator access --------------------------------

select set_config('test.reg2',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000002', '4c000000-0000-4000-8000-000000000004', public.test_purchase_input()))::text,
  true);
select is(current_setting('test.reg2')::jsonb ->> 'ok', 'true', 'member registers a purchase lot');
select is(current_setting('test.reg2')::jsonb -> 'data' ->> 'display_id', '受入-2028-002', 'purchase continues the yearly sequence');
select is(current_setting('test.reg2')::jsonb -> 'data' ->> 'sorting_due_date', '2028-07-31', 'sorting due date defaults to thirty days without a rule');

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000003', true);
select set_config('test.reg3',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000003', '4c000000-0000-4000-8000-000000000005', public.test_harvest_input() || jsonb_build_object('received_date', '2028-05-05')))::text,
  true);
select is(current_setting('test.reg3')::jsonb ->> 'ok', 'true', 'administrator can register');
select is(current_setting('test.reg3')::jsonb -> 'data' ->> 'display_id', '受入-2028-003', 'sequence is shared across users');

select set_config('test.reg1_cross_user',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000006', public.test_harvest_input()))::text,
  true);
select is(current_setting('test.reg1_cross_user')::jsonb -> 'error' ->> 'code', 'IDEMPOTENCY_KEY_REUSED', 'another user cannot replay a stored response');

-- Input validation ---------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);

select set_config('test.val_meta',
  public.receiving_register(jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', 'not-a-uuid', 'correlation_id', '4c000000-0000-4000-8000-000000000007'),
    'input', public.test_harvest_input()))::text,
  true);
select is(current_setting('test.val_meta')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'malformed idempotency key is rejected');
select is(current_setting('test.val_meta')::jsonb -> 'error' -> 'details' ->> 'field', 'meta.idempotency_key', 'meta failure names the field');

select set_config('test.val_tree',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000010', '4c000000-0000-4000-8000-000000000010', public.test_harvest_input() - 'tree_id'))::text,
  true);
select is(current_setting('test.val_tree')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'harvest without a tree is rejected');
select is(current_setting('test.val_tree')::jsonb -> 'error' -> 'details' ->> 'field', 'tree_id', 'missing tree names the field');

select set_config('test.val_supref',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000011', '4c000000-0000-4000-8000-000000000011', public.test_purchase_input() - 'supplier_reference'))::text,
  true);
select is(current_setting('test.val_supref')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'purchase without a supplier reference is rejected');
select is(current_setting('test.val_supref')::jsonb -> 'error' -> 'details' ->> 'field', 'supplier_reference', 'missing supplier reference names the field');

select set_config('test.val_mixed',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000012', '4c000000-0000-4000-8000-000000000012', public.test_harvest_input() || jsonb_build_object('supplier_id', '45000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.val_mixed')::jsonb -> 'error' -> 'details' ->> 'reason', 'not_allowed', 'harvest cannot carry a supplier');

select set_config('test.val_precision',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000013', '4c000000-0000-4000-8000-000000000013', public.test_harvest_input() || jsonb_build_object('total_weight_kg', 1.234)))::text,
  true);
select is(current_setting('test.val_precision')::jsonb -> 'error' -> 'details' ->> 'reason', 'invalid_precision', 'weight beyond 0.01 kg precision is rejected');

select set_config('test.val_zero',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000014', '4c000000-0000-4000-8000-000000000014', public.test_harvest_input() || jsonb_build_object('total_weight_kg', 0)))::text,
  true);
select is(current_setting('test.val_zero')::jsonb -> 'error' -> 'details' ->> 'reason', 'out_of_range', 'zero weight is rejected');

select set_config('test.val_variety',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000015', '4c000000-0000-4000-8000-000000000015', public.test_harvest_input() || jsonb_build_object('variety_id', '41000000-0000-0000-0000-000000000002')))::text,
  true);
select is(current_setting('test.val_variety')::jsonb -> 'error' -> 'details' ->> 'reason', 'variety_mismatch', 'tree variety must match the input variety');

select set_config('test.val_worker',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000016', '4c000000-0000-4000-8000-000000000016', public.test_harvest_input() || jsonb_build_object('worker_id', '46000000-0000-0000-0000-000000000002')))::text,
  true);
select is(current_setting('test.val_worker')::jsonb -> 'error' -> 'details' ->> 'field', 'worker_id', 'inactive worker is rejected');

select set_config('test.val_due',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000017', '4c000000-0000-4000-8000-000000000017', public.test_harvest_input() || jsonb_build_object('sorting_due_date', '2028-04-30')))::text,
  true);
select is(current_setting('test.val_due')::jsonb -> 'error' -> 'details' ->> 'field', 'sorting_due_date', 'sorting due date before the received date is rejected');

-- A stored validation failure replays without re-execution.
select set_config('test.val_tree_replay',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000010', '4c000000-0000-4000-8000-000000000018', public.test_harvest_input() - 'tree_id'))::text,
  true);
select is(current_setting('test.val_tree_replay')::jsonb ->> 'idempotent_replay', 'true', 'stored error envelope is replayed');
select is(current_setting('test.val_tree_replay')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'replayed envelope keeps the error');

-- Validation failures never consume display IDs.
select set_config('test.reg4',
  public.receiving_register(public.test_receiving_req('49000000-0000-4000-8000-000000000004', '4c000000-0000-4000-8000-000000000019', public.test_harvest_input() || jsonb_build_object('received_date', '2028-05-06')))::text,
  true);
select is(current_setting('test.reg4')::jsonb -> 'data' ->> 'display_id', '受入-2028-004', 'failed requests do not burn display ids');

-- Registered state and audit records --------------------------------------------

reset role;
select is(
  (select count(*) from public.receiving_lots where display_id = '受入-2028-001'),
  1::bigint, 'exactly one lot exists for the replayed registration');
select is(
  (select total_weight_kg::text from public.receiving_lots where display_id = '受入-2028-001'),
  '25.50', 'registered weight is stored');
select is(
  (select received_by from public.receiving_lots where display_id = '受入-2028-001'),
  '46000000-0000-0000-0000-000000000001'::uuid, 'registered worker is stored');
select is(
  (select created_by from public.receiving_lots where display_id = '受入-2028-001'),
  '40000000-0000-0000-0000-000000000002'::uuid, 'registration records the actor');
select is(
  (select supplier_reference from public.receiving_lots where display_id = '受入-2028-002'),
  'PO-2028-001', 'purchase supplier reference is stored');
select is(
  (select count(*) from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001'),
  1::bigint, 'a single create history row exists after replay');
select is(
  (select h.operation from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001'),
  'create', 'registration is recorded as a create');
select ok(
  (select h.before_data is null from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001'),
  'create history has no before image');
select is(
  (select r.response ->> 'ok' from private.idempotency_records r
    where r.idempotency_key = '49000000-0000-4000-8000-000000000001'),
  'true', 'success envelope is stored for replay');

-- Correction happy path -----------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);

select set_config('test.cor1',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000020', '4c000000-0000-4000-8000-000000000020',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', current_setting('test.reg1')::jsonb -> 'data' ->> 'receiving_lot_id',
      'expected_version', 1,
      'reason', '計量誤り修正',
      'total_weight_kg', 30.00,
      'origin_name', '修正後テスト農園'
    )))::text,
  true);
select is(current_setting('test.cor1')::jsonb ->> 'ok', 'true', 'member corrects a lot with a reason');
select is(current_setting('test.cor1')::jsonb -> 'data' ->> 'version', '2', 'correction increments the version');
select is(current_setting('test.cor1')::jsonb -> 'data' ->> 'display_id', '受入-2028-001', 'correction keeps the display id');

select set_config('test.cor1_replay',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000020', '4c000000-0000-4000-8000-000000000021',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', current_setting('test.reg1')::jsonb -> 'data' ->> 'receiving_lot_id',
      'expected_version', 1,
      'reason', '計量誤り修正',
      'total_weight_kg', 30.00,
      'origin_name', '修正後テスト農園'
    )))::text,
  true);
select is(current_setting('test.cor1_replay')::jsonb ->> 'idempotent_replay', 'true', 'correction resend is a replay');
select is(current_setting('test.cor1_replay')::jsonb -> 'data' ->> 'version', '2', 'correction replay returns the stored version');

-- Correction guards ---------------------------------------------------------------

select set_config('test.cor_noreason',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000022', '4c000000-0000-4000-8000-000000000022',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', current_setting('test.reg1')::jsonb -> 'data' ->> 'receiving_lot_id',
      'expected_version', 2
    )))::text,
  true);
select is(current_setting('test.cor_noreason')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'correction without a reason is rejected');
select is(current_setting('test.cor_noreason')::jsonb -> 'error' -> 'details' ->> 'field', 'reason', 'missing reason names the field');

select set_config('test.cor_stale',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000023', '4c000000-0000-4000-8000-000000000023',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', current_setting('test.reg1')::jsonb -> 'data' ->> 'receiving_lot_id',
      'expected_version', 1,
      'reason', '古い画面からの修正'
    )))::text,
  true);
select is(current_setting('test.cor_stale')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'stale version is a conflict');
select is(current_setting('test.cor_stale')::jsonb -> 'error' -> 'details' -> 'current' ->> 'version', '2', 'conflict reports the current version');

select set_config('test.cor_notfound',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000024', '4c000000-0000-4000-8000-000000000024',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', '4f000000-0000-4000-8000-000000000000',
      'expected_version', 1,
      'reason', '存在しないロットの修正'
    )))::text,
  true);
select is(current_setting('test.cor_notfound')::jsonb -> 'error' -> 'details' ->> 'reason', 'not_found', 'unknown lot is rejected');

select set_config('test.cor_partial',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000025', '4c000000-0000-4000-8000-000000000025',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', current_setting('test.reg1')::jsonb -> 'data' ->> 'receiving_lot_id',
      'expected_version', 2,
      'reason', '不正入力の確認',
      'origin_name', '  '
    )))::text,
  true);
select is(current_setting('test.cor_partial')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'invalid correction input is rejected');

-- Corrected state and audit records ------------------------------------------------

reset role;
select is(
  (select total_weight_kg::text from public.receiving_lots where display_id = '受入-2028-001'),
  '30.00', 'corrected weight is stored');
select is(
  (select origin_name from public.receiving_lots where display_id = '受入-2028-001'),
  '修正後テスト農園', 'corrected origin is stored');
select is(
  (select version from public.receiving_lots where display_id = '受入-2028-001'),
  2::bigint, 'failed corrections leave the version unchanged');
select is(
  (select count(*) from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001'),
  2::bigint, 'correction appends exactly one history row');
select is(
  (select h.reason from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001' and h.operation = 'correct'),
  '計量誤り修正', 'correction reason is recorded');
select is(
  (select h.before_data ->> 'total_weight_kg' from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001' and h.operation = 'correct'),
  '25.50', 'history keeps the before image');
select is(
  (select h.after_data ->> 'total_weight_kg' from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001' and h.operation = 'correct'),
  '30.00', 'history keeps the after image');
select is(
  (select h.changed_by from public.change_history h
    join public.receiving_lots l on l.id = h.entity_id
    where l.display_id = '受入-2028-001' and h.operation = 'correct'),
  '40000000-0000-0000-0000-000000000002'::uuid, 'history records the actor');

-- Finalized lots cannot be corrected -----------------------------------------------

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values (
  '48000000-0000-0000-0000-000000000001', '受入-2028-TEST-SORTED', 'harvest', '2028-05-03',
  '42000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001',
  '44000000-0000-0000-0000-000000000001', 'RPCテスト農園', '41000000-0000-0000-0000-000000000001',
  10.00, 1, '2028-05-31', '46000000-0000-0000-0000-000000000001'
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
)
values (
  '48000000-0000-0000-0000-000000000011', '選果-2028-TEST-001',
  '48000000-0000-0000-0000-000000000001', '2028-05-04',
  '46000000-0000-0000-0000-000000000001', 10.00, 9.00, 1.00
);
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id, original_weight_kg, current_weight_kg
)
values (
  '48000000-0000-0000-0000-000000000021', '選果-2028-TEST-001-1',
  '48000000-0000-0000-0000-000000000011', '41000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 9.00, 9.00
);
update public.receiving_lots set status = 'sorted'
where id = '48000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select set_config('test.cor_sorted',
  public.receiving_correct(public.test_receiving_req('49000000-0000-4000-8000-000000000026', '4c000000-0000-4000-8000-000000000026',
    public.test_harvest_input() || jsonb_build_object(
      'receiving_lot_id', '48000000-0000-0000-0000-000000000001',
      'expected_version', 1,
      'reason', '選果済みロットの修正'
    )))::text,
  true);
select is(current_setting('test.cor_sorted')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'sorted lot cannot be corrected');
select is(current_setting('test.cor_sorted')::jsonb -> 'error' -> 'details' -> 'current' ->> 'status', 'sorted', 'conflict reports the sorted status');
reset role;

select * from finish();
rollback;
