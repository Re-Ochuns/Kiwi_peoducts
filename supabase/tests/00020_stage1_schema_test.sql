begin;

select no_plan();

select has_table('public', 'varieties', 'varieties table exists');
select has_table('public', 'grades', 'grades table exists');
select has_table('public', 'orchards', 'orchards table exists');
select has_table('public', 'orchard_plots', 'orchard plots table exists');
select has_table('public', 'trees', 'trees table exists');
select has_table('public', 'suppliers', 'suppliers table exists');
select has_table('public', 'workers', 'workers table exists');
select has_table('public', 'storage_locations', 'storage locations table exists');
select has_table('public', 'sorting_deadline_rules', 'sorting deadline rules table exists');
select has_table('public', 'receiving_lots', 'receiving lots table exists');
select has_table('public', 'sorting_results', 'sorting results table exists');
select has_table('public', 'containers', 'containers table exists');
select has_table('public', 'label_jobs', 'label jobs table exists');
select has_table('public', 'label_events', 'label events table exists');
select has_table('public', 'change_history', 'change history table exists');
select has_table('private', 'idempotency_records', 'idempotency records table exists');

select ok(exists(select 1 from pg_extension where extname = 'pg_cron'), 'pg_cron is installed');
select is((select count(*) from cron.job where jobname = 'delete-expired-idempotency-records'), 1::bigint, 'idempotency cleanup is scheduled once');
select ok(exists (
  select 1
  from pg_db_role_setting s
  join pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and setting = 'statement_timeout=8s'
), 'API server statements have an eight second limit');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'stage1-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Stage1 Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'stage1-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Stage1 Member"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'stage1-admin@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Stage1 Admin"}', now(), now());

select private.set_user_access('20000000-0000-0000-0000-000000000002', 'active', array['member']);
select private.set_user_access('20000000-0000-0000-0000-000000000003', 'active', array['administrator']);

insert into public.varieties (id, code, name) values
  ('21000000-0000-0000-0000-000000000001', 'TEST-HW', 'テストヘイワード');
insert into public.orchards (id, code, name) values
  ('23000000-0000-0000-0000-000000000001', 'TEST-ORCHARD', 'テスト農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('24000000-0000-0000-0000-000000000001', '23000000-0000-0000-0000-000000000001', 'TEST-PLOT', 'テスト区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('25000000-0000-0000-0000-000000000001', '24000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'TEST-TREE', 'テスト樹');
insert into public.suppliers (id, management_code, name) values
  ('26000000-0000-0000-0000-000000000001', 'TEST-SUPPLIER', 'テスト仕入先');
insert into public.workers (id, code, display_name) values
  ('27000000-0000-0000-0000-000000000001', 'TEST-WORKER', 'テスト作業者');
insert into public.storage_locations (id, code, name, location_type) values
  ('28000000-0000-0000-0000-000000000001', 'TEST-COLD', 'テスト冷蔵庫', 'cold_storage');
insert into public.sorting_deadline_rules (id, harvest_year, harvest_month, variety_id, deadline_days) values
  ('29000000-0000-0000-0000-000000000001', 2027, 5, '21000000-0000-0000-0000-000000000001', 30),
  ('29000000-0000-0000-0000-000000000002', 2027, 6, '21000000-0000-0000-0000-000000000001', 21);
select is((select count(*) from public.sorting_deadline_rules where variety_id = '21000000-0000-0000-0000-000000000001'),
  2::bigint, 'deadline rules support year and harvest month combinations');

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
update public.varieties set name = '更新済みテストヘイワード'
where id = '21000000-0000-0000-0000-000000000001';
select is((select updated_by from public.varieties where id = '21000000-0000-0000-0000-000000000001'),
  '20000000-0000-0000-0000-000000000002'::uuid, 'audit column records the current actor');

select throws_ok(
  $$insert into public.receiving_lots (
      display_id, source_type, received_on, supplier_id, origin_name, variety_id,
      total_weight_kg, container_count, sorting_due_on, received_by
    ) values (
      '受入-TEST-BAD-SOURCE', 'purchase', '2027-05-01', '26000000-0000-0000-0000-000000000001',
      'テスト産地', '21000000-0000-0000-0000-000000000001', 1.00, 1, '2027-05-31',
      '27000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'purchase requires supplier reference'
);

select throws_ok(
  $$insert into public.receiving_lots (
      display_id, source_type, received_on, supplier_id, supplier_reference, origin_name, variety_id,
      total_weight_kg, container_count, sorting_due_on, received_by
    ) values (
      '受入-TEST-BAD-PRECISION', 'purchase', '2027-05-01', '26000000-0000-0000-0000-000000000001',
      'SUP-1', 'テスト産地', '21000000-0000-0000-0000-000000000001', 1.234, 1, '2027-05-31',
      '27000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'weight precision greater than 0.01 kg is rejected'
);

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values (
  '30000000-0000-0000-0000-000000000001', '受入-2027-TEST-001', 'harvest', '2027-05-01',
  '23000000-0000-0000-0000-000000000001', '24000000-0000-0000-0000-000000000001',
  '25000000-0000-0000-0000-000000000001', 'テスト農園', '21000000-0000-0000-0000-000000000001',
  10.00, 1, '2027-05-31', '27000000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$insert into public.receiving_lots (
      display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name, variety_id,
      total_weight_kg, container_count, sorting_due_on, received_by
    ) select '受入-2027-TEST-001', source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
      variety_id, total_weight_kg, container_count, sorting_due_on, received_by
      from public.receiving_lots where id = '30000000-0000-0000-0000-000000000001'$$,
  '23505', null, 'receiving display id is unique'
);

select throws_ok(
  $$update public.receiving_lots set status = 'sorted'
    where id = '30000000-0000-0000-0000-000000000001'$$,
  '23514', 'sorting result is required', 'lot cannot be sorted without result'
);

insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
)
values (
  '31000000-0000-0000-0000-000000000001', '選果-2027-TEST-001',
  '30000000-0000-0000-0000-000000000001', '2027-05-02',
  '27000000-0000-0000-0000-000000000001', 10.00, 9.00, 1.00
);

insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, location_id
)
values (
  '32000000-0000-0000-0000-000000000001', '選果-2027-TEST-001-1',
  '31000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 9.00, 9.00,
  '28000000-0000-0000-0000-000000000001'
);

insert into public.containers (id, display_id, sorting_result_id, variety_id, grade_id, original_weight_kg, current_weight_kg)
values (
  '32000000-0000-0000-0000-000000000002', '選果-2027-TEST-TEMP', '31000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005', 1.00, 1.00
);
select lives_ok($$delete from public.containers where id = '32000000-0000-0000-0000-000000000002'$$, 'container can be deleted before sorting finalization');

select lives_ok(
  $$update public.receiving_lots set status = 'sorted'
    where id = '30000000-0000-0000-0000-000000000001'$$,
  'consistent whole-lot sorting can be finalized'
);

select throws_ok(
  $$update public.sorting_results set output_weight_kg = 8.50, loss_weight_kg = 1.50
    where id = '31000000-0000-0000-0000-000000000001'$$,
  '23514', 'finalized sorting result cannot be changed', 'finalized sorting weights are immutable'
);

select throws_ok(
  $$update public.containers set original_weight_kg = 8.50, current_weight_kg = 8.50
    where id = '32000000-0000-0000-0000-000000000001'$$,
  '23514', 'finalized sorting container cannot be changed', 'finalized container origin is immutable'
);

select throws_ok(
  $$delete from public.containers where id = '32000000-0000-0000-0000-000000000001'$$,
  '23514', 'finalized sorting container cannot be deleted', 'finalized container cannot be deleted'
);

select throws_ok(
  $$update public.receiving_lots set total_weight_kg = 11.00
    where id = '30000000-0000-0000-0000-000000000001'$$,
  '23514', 'sorted receiving lot cannot be corrected', 'sorted source values are immutable'
);

select throws_ok(
  $$update public.containers set display_id = '選果-CHANGED'
    where id = '32000000-0000-0000-0000-000000000001'$$,
  '23514', 'display_id cannot be changed', 'issued display id is immutable'
);

insert into public.label_jobs (id, container_id) values
  ('33000000-0000-0000-0000-000000000001', '32000000-0000-0000-0000-000000000001');

select throws_ok(
  $$update public.containers set status = 'cold_storage'
    where id = '32000000-0000-0000-0000-000000000001'$$,
  '23514', 'label completion is required', 'container cannot enter stock before label completion'
);

update public.label_jobs
set status = 'printed', printed_copies = 1, completed_at = now(),
    completed_by = '27000000-0000-0000-0000-000000000001'
where id = '33000000-0000-0000-0000-000000000001';

select lives_ok(
  $$update public.containers set status = 'cold_storage'
    where id = '32000000-0000-0000-0000-000000000001'$$,
  'labeled container can enter cold storage'
);

select throws_ok(
  $$update public.containers set status = 'awaiting_label'
    where id = '32000000-0000-0000-0000-000000000001'$$,
  '23514', 'invalid container status transition', 'backward container transition is rejected'
);

insert into public.change_history (
  entity_type, entity_id, operation, after_data, reason, changed_by
)
values (
  'receiving_lot', '30000000-0000-0000-0000-000000000001', 'create',
  '{"status":"awaiting_sorting"}', 'pgTAP fixture', '20000000-0000-0000-0000-000000000003'
);

select throws_ok(
  $$update public.change_history set reason = '改変'
    where entity_id = '30000000-0000-0000-0000-000000000001'$$,
  '23514', 'change history is append-only', 'audit history cannot be changed'
);

set local role anon;
select throws_ok($$select * from public.receiving_lots$$, '42501', null, 'anonymous cannot read business data');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select is((select count(*) from public.receiving_lots), 0::bigint, 'pending user reads no business data');

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select is((select count(*) from public.receiving_lots where display_id = '受入-2027-TEST-001'), 1::bigint, 'active member reads inventory data');
select is((select count(*) from public.change_history), 0::bigint, 'member cannot read audit history');
select throws_ok(
  $$insert into public.varieties (code, name) values ('FORBIDDEN', '禁止')$$,
  '42501', null, 'member cannot mutate tables directly'
);

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000003', true);
select is((select count(*) from public.change_history), 1::bigint, 'administrator reads audit history');
select throws_ok(
  $$select * from private.idempotency_records$$,
  '42501', null, 'authenticated users cannot read idempotency records'
);
reset role;

insert into private.idempotency_records (
  idempotency_key, function_name, request_hash, response, executed_by, created_at, expires_at
)
values (
  '34000000-0000-4000-8000-000000000001', 'test_operation', 'hash', '{"ok":true}',
  '20000000-0000-0000-0000-000000000003', now() - interval '2 days', now() - interval '1 day'
);
select is(private.delete_expired_idempotency_records(), 1::bigint, 'expired idempotency response is deleted');

select * from finish();
rollback;
