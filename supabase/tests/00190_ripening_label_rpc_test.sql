begin;

select no_plan();

-- Fixtures -------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '19100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rl-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"RL Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '19100000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'rl-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"RL Member"}', now(), now());

select private.set_user_access('19100000-0000-0000-0000-000000000002', 'active', array['member']);

insert into public.workers (id, code, display_name, is_active) values
  ('19200000-0000-0000-0000-000000000001', 'RL-WORKER', 'RL作業者', true);

insert into public.storage_locations (id, code, name, location_type) values
  ('19300000-0000-0000-0000-000000000001', 'RL-RIPE', 'RL追熟庫', 'cold_storage');

-- Ripening lot in_progress using seeded variety (ヘイワード) and grade (L).
insert into public.ripening_lots (
  id, display_id, variety_id, grade_id, total_weight_kg, storage_location_id,
  planned_ethylene_at, planned_completion_at, master_snapshot, assigned_worker_id, status
)
values (
  '19400000-0000-0000-0000-000000000001', 'RL-2026-001',
  'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
  8.00, '19300000-0000-0000-0000-000000000001',
  '2026-09-01 09:00:00+09', '2026-09-20 09:00:00+09',
  '{"ethylene_hours":72,"rest_days":7}',
  '19200000-0000-0000-0000-000000000001', 'in_progress'
);

-- Container 1 for label_mark_printed test; container 2 for label_mark_handwritten.
insert into public.containers (
  id, display_id, ripening_lot_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, status, location_id
) values
  ('19500000-0000-0000-0000-000000000001', 'RL-2026-001-1',
   '19400000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
   8.00, 0, 'ethylene_processing', '19300000-0000-0000-0000-000000000001'),
  ('19500000-0000-0000-0000-000000000002', 'RL-2026-001-2',
   '19400000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
   8.00, 0, 'ethylene_processing', '19300000-0000-0000-0000-000000000001');

insert into public.label_jobs (id, container_id) values
  ('19600000-0000-0000-0000-000000000001', '19500000-0000-0000-0000-000000000001'),
  ('19600000-0000-0000-0000-000000000002', '19500000-0000-0000-0000-000000000002');

-- Ethylene injection result for ripening_label_get injection_at field.
insert into public.ripening_work_results (
  ripening_lot_id, work_type, actual_at, actual_temperature,
  location_id, performed_by, checked, operation_id, created_by
) values (
  '19400000-0000-0000-0000-000000000001', 'ethylene_injection',
  '2026-09-01 10:00:00+09', 20.0,
  '19300000-0000-0000-0000-000000000001', '19200000-0000-0000-0000-000000000001',
  true, '19700000-0000-4000-8000-000000000001',
  '19100000-0000-0000-0000-000000000002'
);

-- Planned removal task for ripening_label_get planned_removal_at field.
insert into public.work_tasks (
  id, task_type, ripening_lot_id, scheduled_at, due_at,
  target_url, managed_by_planning, created_by
) values (
  '19800000-0000-0000-0000-000000000001', 'ethylene_removal_check',
  '19400000-0000-0000-0000-000000000001',
  '2026-09-04 09:00:00+09', '2026-09-04 18:00:00+09',
  'https://example.com/tasks/removal', true,
  '19100000-0000-0000-0000-000000000002'
);

-- Function checks ------------------------------------------------------------

select has_function('public'::name, 'ripening_label_get'::name, array['uuid']::name[],
  'ripening_label_get exists');
select isnt_definer('public'::name, 'ripening_label_get'::name, array['uuid']::name[],
  'ripening_label_get runs as invoker (security invoker)');

-- Auth boundary --------------------------------------------------------------

set local role anon;
select throws_ok(
  $$select public.ripening_label_get('19500000-0000-0000-0000-000000000001')$$,
  '42501', null, 'anonymous cannot call ripening_label_get');
reset role;

-- ripening_label_get returns correct data ------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '19100000-0000-0000-0000-000000000002', true);

select is(
  public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'display_id',
  'RL-2026-001-1', 'ripening_label_get returns display_id');
select is(
  (public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'weight_kg')::numeric,
  8.00::numeric, 'ripening_label_get returns original_weight_kg as weight_kg');
select is(
  public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'variety_name',
  'ヘイワード', 'ripening_label_get returns variety name');
select is(
  public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'grade_code',
  'L', 'ripening_label_get returns grade code');
select is(
  public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'location_name',
  'RL追熟庫', 'ripening_label_get returns location name');
select ok(
  (public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'injection_at') is not null,
  'ripening_label_get returns injection_at from ripening_work_results');
select ok(
  (public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'planned_removal_at') is not null,
  'ripening_label_get returns planned_removal_at from managed work_task');
select ok(
  (public.ripening_label_get('19500000-0000-0000-0000-000000000001') ->> 'planned_completion_at') is not null,
  'ripening_label_get returns planned_completion_at from ripening_lot');
select is(
  public.ripening_label_get('00000000-0000-0000-0000-000000000000'),
  null::jsonb, 'ripening_label_get returns null for unknown container');

-- label_mark_printed on ripening: no cold_storage transition -----------------

select set_config('test.rip_printed',
  public.label_mark_printed(jsonb_build_object(
    'meta', jsonb_build_object(
      'idempotency_key', '19a00000-0000-4000-8000-000000000001',
      'correlation_id',  '19a00000-0000-4000-8000-000000000002'),
    'input', jsonb_build_object(
      'label_job_id', '19600000-0000-0000-0000-000000000001',
      'worker_id', '19200000-0000-0000-0000-000000000001')
  ))::text, true);
select is(
  current_setting('test.rip_printed')::jsonb ->> 'ok', 'true',
  'label_mark_printed succeeds on ripening container');
select is(
  (select status from public.label_jobs where id = '19600000-0000-0000-0000-000000000001'),
  'printed', 'label_job status becomes printed after mark_printed');
select is(
  (select status from public.containers where id = '19500000-0000-0000-0000-000000000001'),
  'ethylene_processing',
  'label_mark_printed does not move ripening container to cold_storage');
select ok(
  exists(select 1 from public.change_history
    where entity_type = 'label_job'
      and entity_id = '19600000-0000-0000-0000-000000000001'
      and operation = 'transition'),
  'label_mark_printed writes transition change_history for the label_job');
select ok(
  not exists(select 1 from public.change_history
    where entity_type = 'container'
      and entity_id = '19500000-0000-0000-0000-000000000001'
      and operation = 'transition'),
  'label_mark_printed does not write container transition history for ripening');

-- label_reprint on ripening: container stays in ethylene_processing -----------

select set_config('test.rip_reprint',
  public.label_reprint(jsonb_build_object(
    'meta', jsonb_build_object(
      'idempotency_key', '19a00000-0000-4000-8000-000000000003',
      'correlation_id',  '19a00000-0000-4000-8000-000000000004'),
    'input', jsonb_build_object(
      'label_job_id', '19600000-0000-0000-0000-000000000001',
      'worker_id', '19200000-0000-0000-0000-000000000001',
      'copies', 1, 'reason', '汚れのため再印刷')
  ))::text, true);
select is(
  current_setting('test.rip_reprint')::jsonb ->> 'ok', 'true',
  'label_reprint succeeds on ripening container');
select is(
  (select status from public.containers where id = '19500000-0000-0000-0000-000000000001'),
  'ethylene_processing',
  'label_reprint does not move ripening container to cold_storage');

-- label_mark_handwritten on ripening: no cold_storage transition --------------

select set_config('test.rip_handwritten',
  public.label_mark_handwritten(jsonb_build_object(
    'meta', jsonb_build_object(
      'idempotency_key', '19a00000-0000-4000-8000-000000000005',
      'correlation_id',  '19a00000-0000-4000-8000-000000000006'),
    'input', jsonb_build_object(
      'label_job_id', '19600000-0000-0000-0000-000000000002',
      'worker_id', '19200000-0000-0000-0000-000000000001')
  ))::text, true);
select is(
  current_setting('test.rip_handwritten')::jsonb ->> 'ok', 'true',
  'label_mark_handwritten succeeds on ripening container');
select is(
  (select status from public.label_jobs where id = '19600000-0000-0000-0000-000000000002'),
  'handwritten', 'label_job status becomes handwritten');
select is(
  (select status from public.containers where id = '19500000-0000-0000-0000-000000000002'),
  'ethylene_processing',
  'label_mark_handwritten does not move ripening container to cold_storage');
select ok(
  not exists(select 1 from public.change_history
    where entity_type = 'container'
      and entity_id = '19500000-0000-0000-0000-000000000002'
      and operation = 'transition'),
  'label_mark_handwritten does not write container transition history for ripening');

-- Pending member cannot change label status without auth ---------------------

select set_config('request.jwt.claim.sub', '19100000-0000-0000-0000-000000000001', true);
select is(
  public.label_mark_printed(jsonb_build_object(
    'meta', jsonb_build_object(
      'idempotency_key', '19a00000-0000-4000-8000-000000000007',
      'correlation_id',  '19a00000-0000-4000-8000-000000000008'),
    'input', jsonb_build_object(
      'label_job_id', '19600000-0000-0000-0000-000000000002',
      'worker_id', '19200000-0000-0000-0000-000000000001')
  )) -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'pending user is rejected by label_mark_printed');
reset role;

select * from finish();
rollback;
