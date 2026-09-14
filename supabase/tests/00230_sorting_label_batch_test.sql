begin;

select no_plan();

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'batch-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'batch-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{}', now(), now());

select private.set_user_access(
  'b1000000-0000-0000-0000-000000000002', 'active', array['member']
);

insert into public.varieties (id, code, name) values
  ('b2000000-0000-0000-0000-000000000001', 'BATCH-HW', '一括印刷用ヘイワード');
insert into public.orchards (id, code, name) values
  ('b3000000-0000-0000-0000-000000000001', 'BATCH-ORCHARD', '第一農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('b4000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'BATCH-PLOT', 'A区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('b5000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'BATCH-TREE', '1号樹');
insert into public.workers (id, code, display_name) values
  ('b6000000-0000-0000-0000-000000000001', 'BATCH-WORKER', '一括印刷担当者');
insert into public.storage_locations (id, code, name, location_type) values
  ('b7000000-0000-0000-0000-000000000001', 'BATCH-COLD', '第一冷蔵庫', 'cold_storage');

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id,
  origin_name, variety_id, total_weight_kg, container_count, sorting_due_on,
  received_by
) values (
  'b8000000-0000-0000-0000-000000000001', '受入-BATCH-001', 'harvest',
  '2031-09-01', 'b3000000-0000-0000-0000-000000000001',
  'b4000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000001', '第一農園 A区画',
  'b2000000-0000-0000-0000-000000000001', 18.00, 2, '2031-09-30',
  'b6000000-0000-0000-0000-000000000001'
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
) values (
  'b9000000-0000-0000-0000-000000000001', '選果-BATCH-001',
  'b8000000-0000-0000-0000-000000000001', '2031-09-02',
  'b6000000-0000-0000-0000-000000000001', 18.00, 18.00, 0.00
);
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg
) values
  ('ba000000-0000-0000-0000-000000000001', '選果-BATCH-001-2', 'b9000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000006', 9.50, 9.50),
  ('ba000000-0000-0000-0000-000000000002', '選果-BATCH-001-1', 'b9000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005', 8.50, 8.50);
insert into public.label_jobs (id, container_id) values
  ('bb000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001'),
  ('bb000000-0000-0000-0000-000000000002', 'ba000000-0000-0000-0000-000000000002');

create function public.test_sorting_batch_req(
  key_value text,
  correlation_value text
) returns jsonb language sql as $$
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'idempotency_key', key_value,
      'correlation_id', correlation_value
    ),
    'input', jsonb_build_object(
      'sorting_result_id', 'b9000000-0000-0000-0000-000000000001',
      'worker_id', 'b6000000-0000-0000-0000-000000000001',
      'location_id', 'b7000000-0000-0000-0000-000000000001'
    )
  );
$$;

select has_function('public', 'sorting_labels_get', array['uuid'], 'sorting_labels_get exists');
select has_function('public', 'label_batch_mark_printed', array['jsonb'], 'label_batch_mark_printed exists');
select is_definer('public', 'label_batch_mark_printed', array['jsonb'], 'batch update runs as definer');

set local role anon;
select throws_ok(
  $$select public.sorting_labels_get('b9000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'anonymous cannot read the sorting label batch'
);
select throws_ok(
  $$select public.label_batch_mark_printed('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot complete the sorting label batch'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);
select is(
  public.sorting_labels_get('b9000000-0000-0000-0000-000000000001'),
  null::jsonb,
  'pending users cannot read sorting labels through RLS'
);
select is(
  public.label_batch_mark_printed(public.test_sorting_batch_req(
    'bc000000-0000-4000-8000-000000000001',
    'bd000000-0000-4000-8000-000000000001'
  )) -> 'error' ->> 'code',
  'AUTH_FORBIDDEN',
  'pending users cannot complete a batch'
);

select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select is(
  jsonb_array_length(public.sorting_labels_get(
    'b9000000-0000-0000-0000-000000000001'
  ) -> 'containers'),
  2,
  'the read function returns one label per original container'
);
select is(
  public.sorting_labels_get('b9000000-0000-0000-0000-000000000001')
    -> 'containers' -> 0 ->> 'display_id',
  '選果-BATCH-001-1',
  'labels use grade display order then container display ID'
);

select set_config('test.batch_result', public.label_batch_mark_printed(
  public.test_sorting_batch_req(
    'bc000000-0000-4000-8000-000000000002',
    'bd000000-0000-4000-8000-000000000002'
  )
)::text, true);
select is(current_setting('test.batch_result')::jsonb ->> 'ok', 'true', 'member completes the batch');
select is(current_setting('test.batch_result')::jsonb -> 'data' ->> 'completed_count', '2', 'both labels are completed');
select is((select count(*) from public.label_jobs where status = 'printed'), 2::bigint, 'all jobs are printed');
select is((select count(*) from public.containers where status = 'cold_storage'), 2::bigint, 'all containers move to cold storage');
select is((select count(*) from public.containers where location_id = 'b7000000-0000-0000-0000-000000000001'), 2::bigint, 'location applies to every container');
select is((select count(*) from public.label_events where event_type = 'print'), 2::bigint, 'one print event is recorded per label');

select set_config('test.batch_replay', public.label_batch_mark_printed(
  public.test_sorting_batch_req(
    'bc000000-0000-4000-8000-000000000002',
    'bd000000-0000-4000-8000-000000000003'
  )
)::text, true);
select is(current_setting('test.batch_replay')::jsonb ->> 'idempotent_replay', 'true', 'retry returns the stored result');
select is((select count(*) from public.label_events where event_type = 'print'), 2::bigint, 'retry does not duplicate events');

-- The first row is processed before the already-completed second row is found.
-- The inner exception block must roll the first update back as well.
reset role;
insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id,
  origin_name, variety_id, total_weight_kg, container_count, sorting_due_on,
  received_by
) values (
  'b8000000-0000-0000-0000-000000000002', '受入-BATCH-競合', 'harvest',
  '2031-09-02', 'b3000000-0000-0000-0000-000000000001',
  'b4000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000001', '第一農園 A区画',
  'b2000000-0000-0000-0000-000000000001', 10.00, 2, '2031-09-30',
  'b6000000-0000-0000-0000-000000000001'
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
) values (
  'be000000-0000-0000-0000-000000000001', '選果-BATCH-競合',
  'b8000000-0000-0000-0000-000000000002', '2031-09-03',
  'b6000000-0000-0000-0000-000000000001', 10.00, 10.00, 0.00
);
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg
) values
  ('bf000000-0000-0000-0000-000000000001', '選果-BATCH-競合-1', 'be000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005', 5.00, 5.00),
  ('bf000000-0000-0000-0000-000000000002', '選果-BATCH-競合-2', 'be000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000006', 5.00, 5.00);
insert into public.label_jobs (id, container_id) values
  ('c0000000-0000-0000-0000-000000000001', 'bf000000-0000-0000-0000-000000000001'),
  ('c0000000-0000-0000-0000-000000000002', 'bf000000-0000-0000-0000-000000000002');
update public.label_jobs
set status = 'printed', printed_copies = required_copies,
    completed_at = now(), completed_by = 'b6000000-0000-0000-0000-000000000001'
where id = 'c0000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select is(
  public.label_batch_mark_printed(jsonb_build_object(
    'meta', jsonb_build_object(
      'idempotency_key', 'c1000000-0000-4000-8000-000000000001',
      'correlation_id', 'c2000000-0000-4000-8000-000000000001'
    ),
    'input', jsonb_build_object(
      'sorting_result_id', 'be000000-0000-0000-0000-000000000001',
      'worker_id', 'b6000000-0000-0000-0000-000000000001'
    )
  )) -> 'error' ->> 'code',
  'CONFLICT_STALE',
  'one completed label rejects the whole batch'
);
select is(
  (select status from public.label_jobs where id = 'c0000000-0000-0000-0000-000000000001'),
  'not_printed',
  'an earlier label update is rolled back on a later conflict'
);
select is(
  (select status from public.containers where id = 'bf000000-0000-0000-0000-000000000001'),
  'awaiting_label',
  'an earlier container transition is rolled back on a later conflict'
);
select is(
  (select count(*) from public.label_events where label_job_id in (
    'c0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000002'
  )),
  0::bigint,
  'a conflicted batch leaves no print events'
);

select * from finish();
rollback;
