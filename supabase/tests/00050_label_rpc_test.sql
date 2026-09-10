begin;

select no_plan();

-- Fixtures --------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'label-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Label Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'label-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"Label Member"}', now(), now());

select private.set_user_access('60000000-0000-0000-0000-000000000002', 'active', array['member']);

insert into public.varieties (id, code, name) values
  ('61000000-0000-0000-0000-000000000001', 'LABEL-HW', 'ラベルテストヘイワード');
insert into public.orchards (id, code, name) values
  ('62000000-0000-0000-0000-000000000001', 'LABEL-ORCHARD', 'ラベルテスト農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', 'LABEL-PLOT', 'ラベルテスト区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('64000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 'LABEL-TREE', 'ラベルテスト樹');
insert into public.workers (id, code, display_name, is_active) values
  ('65000000-0000-0000-0000-000000000001', 'LABEL-WORKER-1', 'ラベルテスト作業者', true),
  ('65000000-0000-0000-0000-000000000002', 'LABEL-WORKER-2', 'ラベル無効作業者', false);
insert into public.storage_locations (id, code, name, location_type) values
  ('66000000-0000-0000-0000-000000000001', 'LABEL-COLD', 'ラベルテスト冷蔵庫', 'cold_storage'),
  ('66000000-0000-0000-0000-000000000002', 'LABEL-OTHER', 'ラベルテスト常温棚', 'other');

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values (
  '67000000-0000-0000-0000-000000000001', '受入-2030-TEST-001', 'harvest', '2030-05-01',
  '62000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-000000000001',
  '64000000-0000-0000-0000-000000000001', 'ラベルテスト農園', '61000000-0000-0000-0000-000000000001',
  10.00, 4, '2030-05-31', '65000000-0000-0000-0000-000000000001'
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
)
values (
  '67000000-0000-0000-0000-000000000011', '選果-2030-TEST-001',
  '67000000-0000-0000-0000-000000000001', '2030-05-02',
  '65000000-0000-0000-0000-000000000001', 10.00, 8.00, 2.00
);
insert into public.containers (id, display_id, sorting_result_id, variety_id, grade_id, original_weight_kg, current_weight_kg)
select ('68000000-0000-0000-0000-00000000000' || n)::uuid,
       '選果-2030-TEST-001-' || n,
       '67000000-0000-0000-0000-000000000011',
       '61000000-0000-0000-0000-000000000001',
       'a2000000-0000-0000-0000-000000000005',
       2.00, 2.00
from generate_series(1, 4) as n;
insert into public.label_jobs (id, container_id, required_copies) values
  ('69000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000001', 1),
  ('69000000-0000-0000-0000-000000000002', '68000000-0000-0000-0000-000000000002', 3),
  ('69000000-0000-0000-0000-000000000003', '68000000-0000-0000-0000-000000000003', 1),
  ('69000000-0000-0000-0000-000000000004', '68000000-0000-0000-0000-000000000004', 1);

create function public.test_label_req(key_value text, corr_value text, input_value jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'meta', jsonb_build_object('idempotency_key', key_value, 'correlation_id', corr_value),
    'input', input_value
  );
$$;

-- Function definitions --------------------------------------------------------

select has_function('public'::name, 'label_mark_printed'::name, array['jsonb']::name[], 'label_mark_printed exists');
select has_function('public'::name, 'label_mark_handwritten'::name, array['jsonb']::name[], 'label_mark_handwritten exists');
select has_function('public'::name, 'label_reprint'::name, array['jsonb']::name[], 'label_reprint exists');
select is_definer('public'::name, 'label_mark_printed'::name, array['jsonb']::name[], 'label_mark_printed runs as definer');
select is_definer('public'::name, 'label_mark_handwritten'::name, array['jsonb']::name[], 'label_mark_handwritten runs as definer');
select is_definer('public'::name, 'label_reprint'::name, array['jsonb']::name[], 'label_reprint runs as definer');

-- Auth boundaries -------------------------------------------------------------

set local role anon;
select throws_ok($$select public.label_mark_printed('{}'::jsonb)$$, '42501', null, 'anonymous cannot execute label_mark_printed');
select throws_ok($$select public.label_mark_handwritten('{}'::jsonb)$$, '42501', null, 'anonymous cannot execute label_mark_handwritten');
select throws_ok($$select public.label_reprint('{}'::jsonb)$$, '42501', null, 'anonymous cannot execute label_reprint');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('test.label_noauth',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000090', '6c000000-0000-4000-8000-000000000090',
    jsonb_build_object('label_job_id', '69000000-0000-0000-0000-000000000001', 'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.label_noauth')::jsonb -> 'error' ->> 'code', 'AUTH_REQUIRED', 'missing session is rejected');

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
select set_config('test.label_forbidden',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000091', '6c000000-0000-4000-8000-000000000091',
    jsonb_build_object('label_job_id', '69000000-0000-0000-0000-000000000001', 'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.label_forbidden')::jsonb -> 'error' ->> 'code', 'AUTH_FORBIDDEN', 'pending user cannot mark labels');

-- Mark printed: completion with location ----------------------------------------

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);
select set_config('test.lp1',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'location_id', '66000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lp1')::jsonb ->> 'ok', 'true', 'member marks a label printed');
select is(current_setting('test.lp1')::jsonb -> 'data' ->> 'status', 'printed', 'one copy completes a single-copy job');
select is(current_setting('test.lp1')::jsonb -> 'data' ->> 'printed_copies', '1', 'copies default to one');
select ok((current_setting('test.lp1')::jsonb -> 'data' ->> 'completed_at') is not null, 'completion timestamp is returned');
select is(current_setting('test.lp1')::jsonb -> 'data' ->> 'container_status', 'cold_storage', 'completion moves the container to cold storage');
select is(current_setting('test.lp1')::jsonb -> 'data' ->> 'container_version', '2', 'container version is incremented');
select is(current_setting('test.lp1')::jsonb -> 'data' ->> 'location_id', '66000000-0000-0000-0000-000000000001', 'cold storage location is applied');

select set_config('test.lp1_replay',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000002',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'location_id', '66000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lp1_replay')::jsonb ->> 'idempotent_replay', 'true', 'resend is a replay');

select set_config('test.lp1_reuse',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000003',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'copies', 2)))::text,
  true);
select is(current_setting('test.lp1_reuse')::jsonb -> 'error' ->> 'code', 'IDEMPOTENCY_KEY_REUSED', 'same key with different input is rejected');

select set_config('test.lp1_again',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000002', '6c000000-0000-4000-8000-000000000004',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lp1_again')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'completed job cannot be printed again');
select is(current_setting('test.lp1_again')::jsonb -> 'error' -> 'details' -> 'current' ->> 'status', 'printed', 'conflict reports the completed status');

select set_config('test.lh_on_printed',
  public.label_mark_handwritten(public.test_label_req('6a000000-0000-4000-8000-000000000003', '6c000000-0000-4000-8000-000000000005',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lh_on_printed')::jsonb -> 'error' ->> 'code', 'CONFLICT_STALE', 'completed job cannot switch to handwritten');

-- Partial printing ----------------------------------------------------------------

select set_config('test.lp2_partial',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000004', '6c000000-0000-4000-8000-000000000006',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000002',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'copies', 2)))::text,
  true);
select is(current_setting('test.lp2_partial')::jsonb -> 'data' ->> 'status', 'partially_printed', 'fewer copies than required stay partial');
select ok((current_setting('test.lp2_partial')::jsonb -> 'data' ->> 'completed_at') is null, 'partial printing does not complete the job');
select is(current_setting('test.lp2_partial')::jsonb -> 'data' ->> 'container_status', 'awaiting_label', 'partial printing keeps the container waiting');

select set_config('test.lr_partial',
  public.label_reprint(public.test_label_req('6a000000-0000-4000-8000-000000000005', '6c000000-0000-4000-8000-000000000007',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000002',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'reason', '未完了の再印刷確認')))::text,
  true);
select is(current_setting('test.lr_partial')::jsonb -> 'error' ->> 'code', 'LABEL_NOT_REPRINTABLE', 'partial job cannot be reprinted');
select is(current_setting('test.lr_partial')::jsonb -> 'error' ->> 'category', 'business', 'premature reprint is a business error');

select set_config('test.lp2_complete',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000006', '6c000000-0000-4000-8000-000000000008',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000002',
      'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lp2_complete')::jsonb -> 'data' ->> 'status', 'printed', 'remaining copy completes the job');
select is(current_setting('test.lp2_complete')::jsonb -> 'data' ->> 'container_status', 'cold_storage', 'completion moves the container without a location');

-- Handwritten fallback --------------------------------------------------------------

select set_config('test.lh1',
  public.label_mark_handwritten(public.test_label_req('6a000000-0000-4000-8000-000000000007', '6c000000-0000-4000-8000-000000000009',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000003',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'notes', '印刷機故障のため',
      'location_id', '66000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lh1')::jsonb -> 'data' ->> 'status', 'handwritten', 'handwritten fallback completes the job');
select is(current_setting('test.lh1')::jsonb -> 'data' ->> 'printed_copies', '0', 'handwritten completion keeps zero printed copies');
select is(current_setting('test.lh1')::jsonb -> 'data' ->> 'container_status', 'cold_storage', 'handwritten completion moves the container');

select set_config('test.lh_copies',
  public.label_mark_handwritten(public.test_label_req('6a000000-0000-4000-8000-000000000008', '6c000000-0000-4000-8000-000000000010',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000004',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'copies', 2)))::text,
  true);
select is(current_setting('test.lh_copies')::jsonb -> 'error' -> 'details' ->> 'field', 'copies', 'handwritten rejects copies');
select is(current_setting('test.lh_copies')::jsonb -> 'error' -> 'details' ->> 'reason', 'not_allowed', 'copies are not allowed for handwritten');

-- Reprint ---------------------------------------------------------------------------

select set_config('test.lr1',
  public.label_reprint(public.test_label_req('6a000000-0000-4000-8000-000000000009', '6c000000-0000-4000-8000-000000000011',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'copies', 2,
      'reason', '汚損のため再印刷')))::text,
  true);
select is(current_setting('test.lr1')::jsonb ->> 'ok', 'true', 'printed label can be reprinted with a reason');
select is(current_setting('test.lr1')::jsonb -> 'data' ->> 'status', 'printed', 'reprint keeps the printed status');
select is(current_setting('test.lr1')::jsonb -> 'data' ->> 'printed_copies', '3', 'reprint adds to printed copies');
select is(current_setting('test.lr1')::jsonb -> 'data' ->> 'reprint_count', '1', 'reprint count is incremented');
select is(current_setting('test.lr1')::jsonb -> 'data' ->> 'container_version', '2', 'reprint does not touch the container');

select set_config('test.lr_noreason',
  public.label_reprint(public.test_label_req('6a000000-0000-4000-8000-000000000010', '6c000000-0000-4000-8000-000000000012',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lr_noreason')::jsonb -> 'error' ->> 'code', 'VALIDATION_FAILED', 'reprint without a reason is rejected');
select is(current_setting('test.lr_noreason')::jsonb -> 'error' -> 'details' ->> 'field', 'reason', 'missing reason names the field');

select set_config('test.lr_handwritten',
  public.label_reprint(public.test_label_req('6a000000-0000-4000-8000-000000000011', '6c000000-0000-4000-8000-000000000013',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000003',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'reason', '手書きの再印刷確認')))::text,
  true);
select is(current_setting('test.lr_handwritten')::jsonb -> 'error' ->> 'code', 'LABEL_NOT_REPRINTABLE', 'handwritten job cannot be reprinted');

select set_config('test.lr_notes',
  public.label_reprint(public.test_label_req('6a000000-0000-4000-8000-000000000012', '6c000000-0000-4000-8000-000000000014',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000001',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'reason', '理由', 'notes', '補足')))::text,
  true);
select is(current_setting('test.lr_notes')::jsonb -> 'error' -> 'details' ->> 'field', 'notes', 'reprint rejects notes');

-- Remaining validation ----------------------------------------------------------------

select set_config('test.lp_badloc',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000013', '6c000000-0000-4000-8000-000000000015',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000004',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'location_id', '66000000-0000-0000-0000-000000000002')))::text,
  true);
select is(current_setting('test.lp_badloc')::jsonb -> 'error' -> 'details' ->> 'field', 'location_id', 'non-cold storage location is rejected');
select is(current_setting('test.lp_badloc')::jsonb -> 'error' -> 'details' ->> 'reason', 'invalid_value', 'wrong location type names the reason');

select set_config('test.lp_reason',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000014', '6c000000-0000-4000-8000-000000000016',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000004',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'reason', '不要な理由')))::text,
  true);
select is(current_setting('test.lp_reason')::jsonb -> 'error' -> 'details' ->> 'field', 'reason', 'mark_printed rejects reason');

select set_config('test.lp_zero',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000015', '6c000000-0000-4000-8000-000000000017',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000004',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'copies', 0)))::text,
  true);
select is(current_setting('test.lp_zero')::jsonb -> 'error' -> 'details' ->> 'reason', 'out_of_range', 'zero copies are rejected');

select set_config('test.lp_many',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000016', '6c000000-0000-4000-8000-000000000018',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000004',
      'worker_id', '65000000-0000-0000-0000-000000000001',
      'copies', 1000)))::text,
  true);
select is(current_setting('test.lp_many')::jsonb -> 'error' -> 'details' ->> 'reason', 'out_of_range', 'copies above the cap are rejected');

select set_config('test.lp_worker',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000017', '6c000000-0000-4000-8000-000000000019',
    jsonb_build_object(
      'label_job_id', '69000000-0000-0000-0000-000000000004',
      'worker_id', '65000000-0000-0000-0000-000000000002')))::text,
  true);
select is(current_setting('test.lp_worker')::jsonb -> 'error' -> 'details' ->> 'field', 'worker_id', 'inactive worker is rejected');

select set_config('test.lp_notfound',
  public.label_mark_printed(public.test_label_req('6a000000-0000-4000-8000-000000000018', '6c000000-0000-4000-8000-000000000020',
    jsonb_build_object(
      'label_job_id', '6f000000-0000-4000-8000-000000000000',
      'worker_id', '65000000-0000-0000-0000-000000000001')))::text,
  true);
select is(current_setting('test.lp_notfound')::jsonb -> 'error' -> 'details' ->> 'reason', 'not_found', 'unknown label job is rejected');

-- Persisted state and audit records ----------------------------------------------------

reset role;
select is(
  (select status from public.label_jobs where id = '69000000-0000-0000-0000-000000000001'),
  'printed', 'job one stays printed after reprint');
select is(
  (select printed_copies from public.label_jobs where id = '69000000-0000-0000-0000-000000000001'),
  3, 'printed copies accumulate across print and reprint');
select is(
  (select reprint_count from public.label_jobs where id = '69000000-0000-0000-0000-000000000001'),
  1, 'reprint count is persisted');
select is(
  (select completed_by from public.label_jobs where id = '69000000-0000-0000-0000-000000000001'),
  '65000000-0000-0000-0000-000000000001'::uuid, 'completion records the worker');
select is(
  (select count(*) from public.label_events where label_job_id = '69000000-0000-0000-0000-000000000001'),
  2::bigint, 'print and reprint each record one event');
select is(
  (select notes from public.label_events
    where label_job_id = '69000000-0000-0000-0000-000000000001' and event_type = 'reprint'),
  '汚損のため再印刷', 'reprint reason is stored on the event');
select is(
  (select copies from public.label_events
    where label_job_id = '69000000-0000-0000-0000-000000000001' and event_type = 'reprint'),
  2, 'reprint copies are stored on the event');
select is(
  (select count(*) from public.label_events where label_job_id = '69000000-0000-0000-0000-000000000002' and event_type = 'print'),
  2::bigint, 'partial and completing prints record separate events');
select is(
  (select status from public.containers where id = '68000000-0000-0000-0000-000000000002'),
  'cold_storage', 'container two entered cold storage');
select ok(
  (select location_id is null from public.containers where id = '68000000-0000-0000-0000-000000000002'),
  'completion without a location keeps it unset');
select is(
  (select notes from public.label_events where label_job_id = '69000000-0000-0000-0000-000000000003'),
  '印刷機故障のため', 'handwritten notes are stored');
select is(
  (select status from public.label_jobs where id = '69000000-0000-0000-0000-000000000004'),
  'not_printed', 'rejected requests leave the job untouched');
select is(
  (select count(*) from public.label_events where label_job_id = '69000000-0000-0000-0000-000000000004'),
  0::bigint, 'rejected requests record no events');
select is(
  (select status from public.containers where id = '68000000-0000-0000-0000-000000000004'),
  'awaiting_label', 'rejected requests leave the container waiting');
select is(
  (select count(*) from public.change_history where correlation_id = '6c000000-0000-4000-8000-000000000001'),
  2::bigint, 'completion writes label job and container audit rows');
select is(
  (select count(*) from public.change_history
    where correlation_id = '6c000000-0000-4000-8000-000000000011'
      and entity_type = 'label_job' and operation = 'update' and reason = '汚損のため再印刷'),
  1::bigint, 'reprint audit row keeps the reason');
select is(
  (select r.response ->> 'ok' from private.idempotency_records r
    where r.idempotency_key = '6a000000-0000-4000-8000-000000000001'),
  'true', 'success envelope is stored for replay');

select * from finish();
rollback;
