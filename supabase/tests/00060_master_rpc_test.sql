begin;

select no_plan();

-- Fixtures --------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'master-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Master Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'master-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Master Member"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'master-admin@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Master Admin"}', now(), now());

select private.set_user_access('60000000-0000-0000-0000-000000000002', 'active', array['member']);
select private.set_user_access('60000000-0000-0000-0000-000000000003', 'active', array['administrator']);

-- Request helper (rolled back with the test transaction).

create function public.test_master_req(key_value text, corr_value text, input_value jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', key_value, 'correlation_id', corr_value),
    'input', input_value
  );
$$;

-- Function definitions --------------------------------------------------------

select has_function('public'::name, 'master_register'::name, array['jsonb']::name[], 'master_register exists');
select has_function('public'::name, 'master_update'::name, array['jsonb']::name[], 'master_update exists');
select has_function('public'::name, 'master_deactivate'::name, array['jsonb']::name[], 'master_deactivate exists');
select has_function('public'::name, 'master_activate'::name, array['jsonb']::name[], 'master_activate exists');
select is_definer('public'::name, 'master_register'::name, array['jsonb']::name[], 'master_register runs as definer');
select is_definer('public'::name, 'master_update'::name, array['jsonb']::name[], 'master_update runs as definer');
select is_definer('public'::name, 'master_deactivate'::name, array['jsonb']::name[], 'master_deactivate runs as definer');
select is_definer('public'::name, 'master_activate'::name, array['jsonb']::name[], 'master_activate runs as definer');

select col_has_check('public'::name, 'varieties'::name, 'version'::name, 'varieties gained an optimistic locking version');
select col_has_check('public'::name, 'sorting_deadline_rules'::name, 'version'::name, 'deadline rules gained an optimistic locking version');

-- Auth boundaries -------------------------------------------------------------

set local role anon;
select throws_ok(
  $$select public.master_register('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute master_register'
);
select throws_ok(
  $$select public.master_update('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute master_update'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('test.auth_required',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000090', '6c000000-0000-4000-8000-000000000090',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-NG', 'name', 'MST認証なし')))::text,
  true);
select is(current_setting('test.auth_required')::jsonb -> 'error' ->> 'code', 'AUTH_REQUIRED', 'missing session is rejected');

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
select set_config('test.auth_pending',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000091', '6c000000-0000-4000-8000-000000000091',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-NG', 'name', 'MST承認待ち')))::text,
  true);
select is(current_setting('test.auth_pending')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'pending user is rejected');

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);
select set_config('test.auth_member',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000092', '6c000000-0000-4000-8000-000000000092',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-NG', 'name', 'MSTメンバー')))::text,
  true);
select is(current_setting('test.auth_member')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'member cannot mutate masters');
select is(current_setting('test.auth_member')::jsonb -> 'error' ->> 'category', 'auth', 'member rejection is an auth error');
select set_config('test.auth_member_deact',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000093', '6c000000-0000-4000-8000-000000000093',
    jsonb_build_object('master_type', 'variety', 'master_id', 'a1000000-0000-0000-0000-000000000001', 'expected_version', 1, 'reason', '不可')))::text,
  true);
select is(current_setting('test.auth_member_deact')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'member cannot deactivate masters');
select is((select count(*) from public.varieties where code = 'MST-NG'), 0::bigint, 'forbidden calls write nothing');

-- Register --------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000003', true);
select set_config('test.reg_variety',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-G01', 'name', 'MSTゴールド')))::text,
  true);
select is(current_setting('test.reg_variety')::jsonb ->> 'ok', 'true', 'administrator registers a variety');
select is(current_setting('test.reg_variety')::jsonb ->> 'correlation_id', '6c000000-0000-4000-8000-000000000001', 'correlation id is echoed');
select is(current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_type', 'variety', 'data names the master type');
select is(current_setting('test.reg_variety')::jsonb -> 'data' ->> 'code', 'MST-G01', 'data echoes the stored code');
select is(current_setting('test.reg_variety')::jsonb -> 'data' ->> 'is_active', 'true', 'new master starts active');
select is(current_setting('test.reg_variety')::jsonb -> 'data' ->> 'version', '1', 'new master starts at version 1');
select is(
  (select created_by from public.varieties where code = 'MST-G01'),
  '60000000-0000-0000-0000-000000000003'::uuid, 'creator is recorded on the row');
select is(
  (select count(*) from public.change_history
   where entity_type = 'master'
     and entity_id = (current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id')::uuid
     and operation = 'create'
     and reason = 'マスター登録'
     and changed_by = '60000000-0000-0000-0000-000000000003'
     and correlation_id = '6c000000-0000-4000-8000-000000000001'
     and after_data ->> 'master_type' = 'variety'),
  1::bigint, 'registration writes a create audit record');

-- Idempotent replay and key reuse.

select set_config('test.reg_variety_replay',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000002',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-G01', 'name', 'MSTゴールド')))::text,
  true);
select is(current_setting('test.reg_variety_replay')::jsonb ->> 'idempotent_replay', 'true', 'idempotent resend is a replay');
select is(current_setting('test.reg_variety_replay')::jsonb ->> 'correlation_id', '6c000000-0000-4000-8000-000000000002', 'replay echoes the new correlation id');
select is(
  current_setting('test.reg_variety_replay')::jsonb -> 'data' ->> 'master_id',
  current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
  'replay returns the stored master');
select is((select count(*) from public.varieties where code = 'MST-G01'), 1::bigint, 'replay does not insert twice');

select set_config('test.reg_variety_reuse',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000003',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-G09', 'name', 'MST別品種')))::text,
  true);
select is(current_setting('test.reg_variety_reuse')::jsonb -> 'error' ->> 'code', 'IDEMPOTENCY_KEY_REUSED', 'same key with different input is rejected');

-- Duplicates.

select set_config('test.reg_dup_code',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000002', '6c000000-0000-4000-8000-000000000004',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-G01', 'name', 'MST重複コード')))::text,
  true);
select is(current_setting('test.reg_dup_code')::jsonb -> 'error' ->> 'code', 'MASTER_DUPLICATE', 'duplicate code is rejected');
select is(current_setting('test.reg_dup_code')::jsonb -> 'error' ->> 'category', 'business', 'duplicate is a business error');
select is(current_setting('test.reg_dup_code')::jsonb -> 'error' -> 'details' ->> 'field', 'code', 'duplicate names the field');
select is(
  current_setting('test.reg_dup_code')::jsonb -> 'error' -> 'details' -> 'existing' ->> 'master_id',
  current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
  'duplicate reports the existing master');
select is(current_setting('test.reg_dup_code')::jsonb -> 'error' -> 'details' -> 'existing' ->> 'is_active', 'true', 'duplicate reports the existing active state');

select set_config('test.reg_dup_name',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000003', '6c000000-0000-4000-8000-000000000005',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-G02', 'name', 'MSTゴールド')))::text,
  true);
select is(current_setting('test.reg_dup_name')::jsonb -> 'error' ->> 'code', 'MASTER_DUPLICATE', 'duplicate variety name is rejected');
select is(current_setting('test.reg_dup_name')::jsonb -> 'error' -> 'details' ->> 'field', 'name', 'duplicate variety name names the field');

-- Validation.

select set_config('test.reg_grade',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000004', '6c000000-0000-4000-8000-000000000006',
    jsonb_build_object('master_type', 'grade', 'display_order', 9)))::text,
  true);
select is(current_setting('test.reg_grade')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'grades cannot be registered');
select is(current_setting('test.reg_grade')::jsonb -> 'error' -> 'details' ->> 'reason', 'not_allowed', 'fixed grade candidates are closed');

select set_config('test.reg_bad_type',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000005', '6c000000-0000-4000-8000-000000000007',
    jsonb_build_object('master_type', 'unknown', 'code', 'X', 'name', 'X')))::text,
  true);
select is(current_setting('test.reg_bad_type')::jsonb -> 'error' -> 'details' ->> 'field', 'master_type', 'unknown master type names the field');

select set_config('test.reg_missing_name',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000006', '6c000000-0000-4000-8000-000000000008',
    jsonb_build_object('master_type', 'variety', 'code', 'MST-G03')))::text,
  true);
select is(current_setting('test.reg_missing_name')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'missing required field is rejected');
select is(current_setting('test.reg_missing_name')::jsonb -> 'error' -> 'details' ->> 'field', 'name', 'missing field is named');
select is(current_setting('test.reg_missing_name')::jsonb -> 'error' -> 'details' ->> 'reason', 'required', 'missing field reason is required');

-- Hierarchy registration.

select set_config('test.reg_orchard',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000007', '6c000000-0000-4000-8000-000000000009',
    jsonb_build_object('master_type', 'orchard', 'code', 'MST-O01', 'name', 'MST農園')))::text,
  true);
select is(current_setting('test.reg_orchard')::jsonb ->> 'ok', 'true', 'administrator registers an orchard');

select set_config('test.reg_plot',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000008', '6c000000-0000-4000-8000-000000000010',
    jsonb_build_object('master_type', 'orchard_plot',
      'orchard_id', current_setting('test.reg_orchard')::jsonb -> 'data' ->> 'master_id',
      'code', 'MST-P01', 'name', 'MST区画')))::text,
  true);
select is(current_setting('test.reg_plot')::jsonb ->> 'ok', 'true', 'administrator registers a plot under the orchard');

select set_config('test.reg_plot_bad_parent',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000009', '6c000000-0000-4000-8000-000000000011',
    jsonb_build_object('master_type', 'orchard_plot',
      'orchard_id', '6f000000-0000-4000-8000-000000000099',
      'code', 'MST-P09', 'name', 'MST迷子区画')))::text,
  true);
select is(current_setting('test.reg_plot_bad_parent')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'plot requires an existing active orchard');
select is(current_setting('test.reg_plot_bad_parent')::jsonb -> 'error' -> 'details' ->> 'field', 'orchard_id', 'missing parent names the field');

select set_config('test.reg_tree',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000010', '6c000000-0000-4000-8000-000000000012',
    jsonb_build_object('master_type', 'tree',
      'plot_id', current_setting('test.reg_plot')::jsonb -> 'data' ->> 'master_id',
      'variety_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'code', 'MST-T01', 'name', 'MST樹1')))::text,
  true);
select is(current_setting('test.reg_tree')::jsonb ->> 'ok', 'true', 'administrator registers a tree');
select is(
  current_setting('test.reg_tree')::jsonb -> 'data' ->> 'plot_id',
  current_setting('test.reg_plot')::jsonb -> 'data' ->> 'master_id',
  'tree data returns its parents');

-- Remaining master types.

select set_config('test.reg_supplier',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000011', '6c000000-0000-4000-8000-000000000013',
    jsonb_build_object('master_type', 'supplier', 'management_code', 'MST-S01', 'name', 'MST仕入先')))::text,
  true);
select is(current_setting('test.reg_supplier')::jsonb ->> 'ok', 'true', 'administrator registers a supplier');

select set_config('test.reg_worker',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000012', '6c000000-0000-4000-8000-000000000014',
    jsonb_build_object('master_type', 'worker', 'code', 'MST-W01', 'display_name', 'MST作業者', 'reason', '臨時作業者追加')))::text,
  true);
select is(current_setting('test.reg_worker')::jsonb ->> 'ok', 'true', 'administrator registers a worker');
select is(
  (select count(*) from public.change_history
   where entity_type = 'master'
     and entity_id = (current_setting('test.reg_worker')::jsonb -> 'data' ->> 'master_id')::uuid
     and operation = 'create' and reason = '臨時作業者追加'),
  1::bigint, 'an explicit registration reason is recorded');

select set_config('test.reg_location_bad',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000013', '6c000000-0000-4000-8000-000000000015',
    jsonb_build_object('master_type', 'storage_location', 'code', 'MST-C01', 'name', 'MST冷蔵庫', 'location_type', 'freezer')))::text,
  true);
select is(current_setting('test.reg_location_bad')::jsonb -> 'error' -> 'details' ->> 'field', 'location_type', 'unknown location type is rejected');

select set_config('test.reg_location',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000014', '6c000000-0000-4000-8000-000000000016',
    jsonb_build_object('master_type', 'storage_location', 'code', 'MST-C01', 'name', 'MST冷蔵庫', 'location_type', 'cold_storage')))::text,
  true);
select is(current_setting('test.reg_location')::jsonb ->> 'ok', 'true', 'administrator registers a storage location');

select set_config('test.reg_rule',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000015', '6c000000-0000-4000-8000-000000000017',
    jsonb_build_object('master_type', 'sorting_deadline_rule', 'harvest_year', 2028, 'harvest_month', 5,
      'variety_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'deadline_days', 21)))::text,
  true);
select is(current_setting('test.reg_rule')::jsonb ->> 'ok', 'true', 'administrator registers a deadline rule');

select set_config('test.reg_rule_dup',
  public.master_register(public.test_master_req('69000000-0000-4000-8000-000000000016', '6c000000-0000-4000-8000-000000000018',
    jsonb_build_object('master_type', 'sorting_deadline_rule', 'harvest_year', 2028, 'harvest_month', 5,
      'variety_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'deadline_days', 30)))::text,
  true);
select is(current_setting('test.reg_rule_dup')::jsonb -> 'error' ->> 'code', 'MASTER_DUPLICATE', 'duplicate rule combination is rejected');

-- Update ----------------------------------------------------------------------

select set_config('test.upd_variety',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000020', '6c000000-0000-4000-8000-000000000020',
    jsonb_build_object('master_type', 'variety',
      'master_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '名称修正',
      'code', 'MST-G01', 'name', 'MSTゴールド改')))::text,
  true);
select is(current_setting('test.upd_variety')::jsonb ->> 'ok', 'true', 'administrator updates a variety');
select is(current_setting('test.upd_variety')::jsonb -> 'data' ->> 'name', 'MSTゴールド改', 'update returns the new value');
select is(current_setting('test.upd_variety')::jsonb -> 'data' ->> 'version', '2', 'update increments the version');
select is(
  (select updated_by from public.varieties where code = 'MST-G01'),
  '60000000-0000-0000-0000-000000000003'::uuid, 'updater is recorded on the row');
select is(
  (select count(*) from public.change_history
   where entity_type = 'master'
     and entity_id = (current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id')::uuid
     and operation = 'update'
     and before_data ->> 'name' = 'MSTゴールド'
     and after_data ->> 'name' = 'MSTゴールド改'
     and reason = '名称修正'),
  1::bigint, 'update writes a before and after audit record');

select set_config('test.upd_stale',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000021', '6c000000-0000-4000-8000-000000000021',
    jsonb_build_object('master_type', 'variety',
      'master_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '古い画面から', 'code', 'MST-G01', 'name', 'MST古い名前')))::text,
  true);
select is(current_setting('test.upd_stale')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'stale expected version is a conflict');
select is(current_setting('test.upd_stale')::jsonb -> 'error' ->> 'category', 'conflict', 'stale version has the conflict category');
select is(current_setting('test.upd_stale')::jsonb -> 'error' -> 'details' -> 'current' ->> 'version', '2', 'conflict reports the current version');

select set_config('test.upd_missing_reason',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000022', '6c000000-0000-4000-8000-000000000022',
    jsonb_build_object('master_type', 'variety',
      'master_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'code', 'MST-G01', 'name', 'MST理由なし')))::text,
  true);
select is(current_setting('test.upd_missing_reason')::jsonb -> 'error' -> 'details' ->> 'field', 'reason', 'update requires a reason');

select set_config('test.upd_unknown',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000023', '6c000000-0000-4000-8000-000000000023',
    jsonb_build_object('master_type', 'variety',
      'master_id', '6f000000-0000-4000-8000-000000000098',
      'expected_version', 1, 'reason', '存在しない', 'code', 'MST-NF', 'name', 'MST不明')))::text,
  true);
select is(current_setting('test.upd_unknown')::jsonb -> 'error' -> 'details' ->> 'field', 'master_id', 'unknown master is a validation failure');
select is(current_setting('test.upd_unknown')::jsonb -> 'error' -> 'details' ->> 'reason', 'not_found', 'unknown master reason is not_found');

select set_config('test.upd_tree_parent',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000024', '6c000000-0000-4000-8000-000000000024',
    jsonb_build_object('master_type', 'tree',
      'master_id', current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '区画変更',
      'plot_id', 'a4000000-0000-0000-0000-000000000001',
      'code', 'MST-T01', 'name', 'MST樹1')))::text,
  true);
select is(current_setting('test.upd_tree_parent')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'tree parent cannot change');
select is(current_setting('test.upd_tree_parent')::jsonb -> 'error' -> 'details' ->> 'reason', 'immutable', 'tree parent change reason is immutable');

-- Grade updates: fixed candidates allow display order and active flag only.

select set_config('test.upd_grade_dup',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000025', '6c000000-0000-4000-8000-000000000025',
    jsonb_build_object('master_type', 'grade',
      'master_id', 'a2000000-0000-0000-0000-000000000001',
      'expected_version', 1, 'reason', '表示順変更', 'display_order', 2)))::text,
  true);
select is(current_setting('test.upd_grade_dup')::jsonb -> 'error' ->> 'code', 'MASTER_DUPLICATE', 'duplicate display order is rejected');
select is(
  current_setting('test.upd_grade_dup')::jsonb -> 'error' -> 'details' -> 'existing' ->> 'master_id',
  'a2000000-0000-0000-0000-000000000002', 'duplicate display order reports the holder');

select set_config('test.upd_grade',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000026', '6c000000-0000-4000-8000-000000000026',
    jsonb_build_object('master_type', 'grade',
      'master_id', 'a2000000-0000-0000-0000-000000000001',
      'expected_version', 1, 'reason', '表示順変更', 'display_order', 99)))::text,
  true);
select is(current_setting('test.upd_grade')::jsonb ->> 'ok', 'true', 'grade display order can change');
select is(current_setting('test.upd_grade')::jsonb -> 'data' ->> 'display_order', '99', 'grade data returns the new order');
select is((select code from public.grades where id = 'a2000000-0000-0000-0000-000000000001'), '5L', 'grade code is untouched');

-- Deactivate and activate -----------------------------------------------------

select set_config('test.deact_orchard_used',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000030', '6c000000-0000-4000-8000-000000000030',
    jsonb_build_object('master_type', 'orchard',
      'master_id', current_setting('test.reg_orchard')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '閉園')))::text,
  true);
select is(current_setting('test.deact_orchard_used')::jsonb -> 'error' ->> 'code', 'MASTER_IN_USE', 'orchard with active plots cannot be deactivated');
select is(
  current_setting('test.deact_orchard_used')::jsonb -> 'error' -> 'details' -> 'dependencies' -> 0 ->> 'entity',
  'orchard_plot', 'in-use error lists the blocking dependents');

select set_config('test.deact_variety_used',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000031', '6c000000-0000-4000-8000-000000000031',
    jsonb_build_object('master_type', 'variety',
      'master_id', current_setting('test.reg_variety')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '取扱終了')))::text,
  true);
select is(current_setting('test.deact_variety_used')::jsonb -> 'error' ->> 'code', 'MASTER_IN_USE', 'variety with active trees and rules cannot be deactivated');
select is(
  jsonb_array_length(current_setting('test.deact_variety_used')::jsonb -> 'error' -> 'details' -> 'dependencies'),
  2, 'variety in-use error lists both dependent kinds');

select set_config('test.deact_tree',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000032', '6c000000-0000-4000-8000-000000000032',
    jsonb_build_object('master_type', 'tree',
      'master_id', current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '伐採')))::text,
  true);
select is(current_setting('test.deact_tree')::jsonb ->> 'ok', 'true', 'leaf master can be deactivated');
select is(current_setting('test.deact_tree')::jsonb -> 'data' ->> 'is_active', 'false', 'deactivation returns the inactive state');
select is(current_setting('test.deact_tree')::jsonb -> 'data' ->> 'version', '2', 'deactivation increments the version');
select is(
  (select count(*) from public.trees
   where id = (current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id')::uuid
     and is_active = false),
  1::bigint, 'deactivated master is preserved, not deleted');
select is(
  (select count(*) from public.change_history
   where entity_type = 'master'
     and entity_id = (current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id')::uuid
     and operation = 'transition' and reason = '伐採'),
  1::bigint, 'deactivation writes a transition audit record');

select set_config('test.deact_tree_again',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000033', '6c000000-0000-4000-8000-000000000033',
    jsonb_build_object('master_type', 'tree',
      'master_id', current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '再度伐採')))::text,
  true);
select is(current_setting('test.deact_tree_again')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'deactivating an inactive master is a conflict');
select is(current_setting('test.deact_tree_again')::jsonb -> 'error' -> 'details' -> 'current' ->> 'is_active', 'false', 'conflict reports the inactive state');

select set_config('test.deact_plot',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000034', '6c000000-0000-4000-8000-000000000034',
    jsonb_build_object('master_type', 'orchard_plot',
      'master_id', current_setting('test.reg_plot')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '区画整理')))::text,
  true);
select is(current_setting('test.deact_plot')::jsonb ->> 'ok', 'true', 'plot deactivates once its trees are inactive');

select set_config('test.deact_orchard',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000035', '6c000000-0000-4000-8000-000000000035',
    jsonb_build_object('master_type', 'orchard',
      'master_id', current_setting('test.reg_orchard')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '閉園')))::text,
  true);
select is(current_setting('test.deact_orchard')::jsonb ->> 'ok', 'true', 'orchard deactivates once its plots are inactive');

select set_config('test.act_tree_blocked',
  public.master_activate(public.test_master_req('69000000-0000-4000-8000-000000000036', '6c000000-0000-4000-8000-000000000036',
    jsonb_build_object('master_type', 'tree',
      'master_id', current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '再稼働')))::text,
  true);
select is(current_setting('test.act_tree_blocked')::jsonb -> 'error' ->> 'code', 'MASTER_PARENT_INACTIVE', 'tree cannot reactivate under an inactive plot');
select is(
  current_setting('test.act_tree_blocked')::jsonb -> 'error' -> 'details' -> 'parent' ->> 'master_type',
  'orchard_plot', 'parent-inactive error names the parent');

select set_config('test.act_orchard',
  public.master_activate(public.test_master_req('69000000-0000-4000-8000-000000000037', '6c000000-0000-4000-8000-000000000037',
    jsonb_build_object('master_type', 'orchard',
      'master_id', current_setting('test.reg_orchard')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '再開園')))::text,
  true);
select is(current_setting('test.act_orchard')::jsonb ->> 'ok', 'true', 'orchard reactivates');

select set_config('test.act_plot',
  public.master_activate(public.test_master_req('69000000-0000-4000-8000-000000000038', '6c000000-0000-4000-8000-000000000038',
    jsonb_build_object('master_type', 'orchard_plot',
      'master_id', current_setting('test.reg_plot')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '区画再開')))::text,
  true);
select is(current_setting('test.act_plot')::jsonb ->> 'ok', 'true', 'plot reactivates under an active orchard');

select set_config('test.act_tree',
  public.master_activate(public.test_master_req('69000000-0000-4000-8000-000000000039', '6c000000-0000-4000-8000-000000000039',
    jsonb_build_object('master_type', 'tree',
      'master_id', current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '再稼働')))::text,
  true);
select is(current_setting('test.act_tree')::jsonb ->> 'ok', 'true', 'tree reactivates under active parents');
select is(current_setting('test.act_tree')::jsonb -> 'data' ->> 'version', '3', 'reactivation increments the version');

select set_config('test.act_tree_again',
  public.master_activate(public.test_master_req('69000000-0000-4000-8000-000000000040', '6c000000-0000-4000-8000-000000000040',
    jsonb_build_object('master_type', 'tree',
      'master_id', current_setting('test.reg_tree')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 3, 'reason', '再稼働')))::text,
  true);
select is(current_setting('test.act_tree_again')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'activating an active master is a conflict');

-- Inactive masters stay editable so they can be fixed before reactivation.

select set_config('test.deact_supplier',
  public.master_deactivate(public.test_master_req('69000000-0000-4000-8000-000000000041', '6c000000-0000-4000-8000-000000000041',
    jsonb_build_object('master_type', 'supplier',
      'master_id', current_setting('test.reg_supplier')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 1, 'reason', '取引停止')))::text,
  true);
select is(current_setting('test.deact_supplier')::jsonb ->> 'ok', 'true', 'supplier deactivates');

select set_config('test.upd_supplier_inactive',
  public.master_update(public.test_master_req('69000000-0000-4000-8000-000000000042', '6c000000-0000-4000-8000-000000000042',
    jsonb_build_object('master_type', 'supplier',
      'master_id', current_setting('test.reg_supplier')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 2, 'reason', '社名変更',
      'management_code', 'MST-S01', 'name', 'MST仕入先改')))::text,
  true);
select is(current_setting('test.upd_supplier_inactive')::jsonb ->> 'ok', 'true', 'inactive master can still be corrected');

select set_config('test.act_supplier',
  public.master_activate(public.test_master_req('69000000-0000-4000-8000-000000000043', '6c000000-0000-4000-8000-000000000043',
    jsonb_build_object('master_type', 'supplier',
      'master_id', current_setting('test.reg_supplier')::jsonb -> 'data' ->> 'master_id',
      'expected_version', 3, 'reason', '取引再開')))::text,
  true);
select is(current_setting('test.act_supplier')::jsonb ->> 'ok', 'true', 'supplier reactivates');
select is(current_setting('test.act_supplier')::jsonb -> 'data' ->> 'name', 'MST仕入先改', 'reactivation returns the corrected fields');

reset role;

select * from finish();
rollback;
