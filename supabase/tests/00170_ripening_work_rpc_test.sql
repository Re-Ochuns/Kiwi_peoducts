begin;

select no_plan();

select has_table('public', 'customers', 'customers table exists');
select has_table('public', 'shipping_destinations', 'shipping destinations table exists');
select has_table('public', 'orders', 'orders table exists');
select has_table('public', 'ripening_lots', 'ripening lots table exists');
select has_table('public', 'ripening_allocations', 'ripening allocations table exists');
select has_table('public', 'inventory_reservations', 'inventory reservations table exists');
select has_table('public', 'work_tasks', 'work tasks table exists');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '41000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 's2-pending@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"S2 Pending"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '41000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 's2-member@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"S2 Member"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '41000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 's2-admin@example.com', '', now(), '{"provider":"google","providers":["google"]}', '{"full_name":"S2 Admin"}', now(), now());

select private.set_user_access('41000000-0000-0000-0000-000000000002', 'active', array['member']);
select private.set_user_access('41000000-0000-0000-0000-000000000003', 'active', array['administrator']);

insert into public.varieties (id, code, name) values
  ('42000000-0000-0000-0000-000000000001', 'S2-HW', 'S2ヘイワード');
insert into public.workers (id, code, display_name) values
  ('43000000-0000-0000-0000-000000000001', 'S2-WORKER', 'S2作業者');
insert into public.storage_locations (id, code, name, location_type) values
  ('44000000-0000-0000-0000-000000000001', 'S2-COLD', 'S2冷蔵庫', 'cold_storage'),
  ('44000000-0000-0000-0000-000000000002', 'S3-ACTUAL', '実績追熟庫', 'cold_storage'),
  ('44000000-0000-0000-0000-000000000003', 'S3-REST', '実績寝かせ庫', 'cold_storage');

insert into public.customers (
  id, customer_code, name, nickname, postal_code, address
)
values (
  '45000000-0000-0000-0000-000000000001', 'S2-CUSTOMER', 'S2顧客', 'お得意様', '000-0000', 'テスト県テスト市1-1'
);

insert into public.shipping_destinations (
  id, customer_id, destination_name, recipient_name, postal_code, address
)
values
  ('46000000-0000-0000-0000-000000000001', '45000000-0000-0000-0000-000000000001', '自宅', 'S2顧客', '000-0000', 'テスト県テスト市1-1'),
  ('46000000-0000-0000-0000-000000000002', '45000000-0000-0000-0000-000000000001', '贈答先', '贈答先様', '111-1111', 'テスト県テスト市2-2');

select is(
  (select count(*) from public.shipping_destinations where customer_id = '45000000-0000-0000-0000-000000000001'),
  2::bigint,
  'one customer has multiple shipping destinations'
);

insert into public.orders (
  id, order_number, customer_id, shipping_destination_id, ordered_on, scheduled_ship_on,
  variety_id, grade_id, ordered_weight_kg, shipping_destination_snapshot, status
)
values (
  '47000000-0000-0000-0000-000000000001', 'ORD-S2-001',
  '45000000-0000-0000-0000-000000000001', '46000000-0000-0000-0000-000000000001',
  '2027-06-01', '2027-06-20', '42000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 6.00,
  '{"recipient_name":"S2顧客","postal_code":"000-0000","address":"テスト県テスト市1-1"}',
  'confirmed'
);

insert into public.orchards (id, code, name) values
  ('48000000-0000-0000-0000-000000000001', 'S2-ORCHARD', 'S2農園');
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('48100000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000001', 'S2-PLOT', 'S2区画');
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('48200000-0000-0000-0000-000000000001', '48100000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001', 'S2-TREE', 'S2樹');
insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values (
  '48300000-0000-0000-0000-000000000001', '受入-2027-S2-001', 'harvest', '2027-05-01',
  '48000000-0000-0000-0000-000000000001', '48100000-0000-0000-0000-000000000001',
  '48200000-0000-0000-0000-000000000001', 'S2農園', '42000000-0000-0000-0000-000000000001',
  10.00, 1, '2027-05-31', '43000000-0000-0000-0000-000000000001'
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by, input_weight_kg, output_weight_kg, loss_weight_kg
)
values (
  '48400000-0000-0000-0000-000000000001', '選果-2027-S2-001',
  '48300000-0000-0000-0000-000000000001', '2027-05-02',
  '43000000-0000-0000-0000-000000000001', 10.00, 10.00, 0
);
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id, original_weight_kg, current_weight_kg,
  location_id
)
values (
  '48500000-0000-0000-0000-000000000001', '選果-2027-S2-001-1',
  '48400000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 10.00, 10.00,
  '44000000-0000-0000-0000-000000000001'
);
update public.receiving_lots set status = 'sorted'
where id = '48300000-0000-0000-0000-000000000001';
insert into public.label_jobs (
  id, container_id, status, required_copies, printed_copies, completed_at, completed_by
)
values (
  '48600000-0000-0000-0000-000000000001', '48500000-0000-0000-0000-000000000001',
  'printed', 1, 1, now(), '43000000-0000-0000-0000-000000000001'
);
update public.containers set status = 'cold_storage'
where id = '48500000-0000-0000-0000-000000000001';

insert into public.ripening_lots (
  id, display_id, variety_id, grade_id, total_weight_kg, storage_location_id,
  planned_ethylene_at, planned_completion_at, master_snapshot, harvest_year, harvest_month, assigned_worker_id
)
values (
  '49000000-0000-0000-0000-000000000001', '追熟-2027-001',
  '42000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
  10.00, '44000000-0000-0000-0000-000000000001', '2027-06-10 09:00+09',
  '2027-06-20 09:00+09', '{"ethylene_hours":72,"rest_days":7,"shippable_days":5,"best_before_days":7}', 2026, 11,
  '43000000-0000-0000-0000-000000000001'
);

insert into public.ripening_allocations (
  id, ripening_lot_id, allocation_type, order_id, allocated_weight_kg
)
values
  ('49100000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001', 'order', '47000000-0000-0000-0000-000000000001', 6.00),
  ('49100000-0000-0000-0000-000000000002', '49000000-0000-0000-0000-000000000001', 'reserve', null, 4.00);

select is(
  (select allocated_weight_kg::numeric from public.ripening_lots where id = '49000000-0000-0000-0000-000000000001'),
  10.00::numeric,
  'lot allocation total is maintained'
);
select is(
  (select use_type from public.ripening_lots where id = '49000000-0000-0000-0000-000000000001'),
  'mixed',
  'order and reserve allocations derive mixed use type'
);
select is(
  (select allocated_weight_kg::numeric from public.orders where id = '47000000-0000-0000-0000-000000000001'),
  6.00::numeric,
  'order allocation total is maintained'
);

insert into public.inventory_reservations (
  id, ripening_lot_id, container_id, reserved_weight_kg
)
values (
  '49200000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001',
  '48500000-0000-0000-0000-000000000001', 10.00
);

select is(
  (select reserved_weight_kg::numeric from public.containers where id = '48500000-0000-0000-0000-000000000001'),
  10.00::numeric,
  'container reserved weight is maintained atomically'
);
select is(
  (select (current_weight_kg - reserved_weight_kg)::numeric from public.containers where id = '48500000-0000-0000-0000-000000000001'),
  0.00::numeric,
  'available weight is current weight minus reservations'
);

-- Keep 2kg in the source container while the 8kg order/reserve lot starts.
update public.ripening_allocations set allocated_weight_kg=2
  where id='49100000-0000-0000-0000-000000000002';
update public.ripening_lots set total_weight_kg=8
  where id='49000000-0000-0000-0000-000000000001';
update public.inventory_reservations set reserved_weight_kg=8
  where id='49200000-0000-0000-0000-000000000001';
update public.ripening_lots set status='confirmed'
  where id='49000000-0000-0000-0000-000000000001';
select private.project_ripening_tasks('49000000-0000-0000-0000-000000000001',
  '41000000-0000-0000-0000-000000000002','test plan',gen_random_uuid());

create function pg_temp.work_req(extra jsonb default '{}'::jsonb, operation uuid default gen_random_uuid())
returns jsonb language sql as $$
  select jsonb_build_object('meta',jsonb_build_object(
    'idempotency_key',operation,'correlation_id',gen_random_uuid()),
    'input',jsonb_build_object(
      'ripening_lot_id','49000000-0000-0000-0000-000000000001',
      'expected_version',(select version from public.ripening_lots where id='49000000-0000-0000-0000-000000000001'),
      'location_id','44000000-0000-0000-0000-000000000001',
      'performed_by','43000000-0000-0000-0000-000000000001',
      'actual_temperature',20,'checked',true) || extra);
$$;
create temporary table initial_tasks as select * from public.work_tasks;
grant select on initial_tasks to authenticated;
create temporary table work_responses (name text primary key, req jsonb, result jsonb);
grant all on work_responses to authenticated;

select ok(not has_function_privilege('anon','public.ripening_ethylene_injection_complete(jsonb)','EXECUTE'),
  'anonymous cannot invoke injection');
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req())->'error'->>'code',
  'AUTH_FORBIDDEN','pending user denied');
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req('{"checked":false}'))->'error'->>'code',
  'CONFIRMATION_REQUIRED','unchecked injection rejected');
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req('{"checked":"true"}'))->'error'->>'code',
  'CONFIRMATION_REQUIRED','text true is not a confirmation');
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req('{"actual_at":"2027-01-01"}'))->'error'->>'code',
  'VALIDATION_FAILED','timezone required on explicit actual time');
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req('{"actual_temperature":"20"}'))->'error'->>'code',
  'VALIDATION_FAILED','temperature must be numeric');
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req('{"expected_version":999}'))->'error'->>'code',
  'CONFLICT_STALE','stale version rejected');
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req('{"extend_days":1}'))->'error'->>'code',
  'VALIDATION_FAILED','unsupported extension cannot be requested');
select is(public.ripening_ripeness_complete(pg_temp.work_req())->'error'->>'code',
  'INVALID_WORK_STATE','cannot skip injection');

-- Force a business error after source/output movement to verify the action
-- subtransaction rolls back inventory, orders, tasks and history together.
reset role;
create function private.test_ripening_work_failure() returns trigger
language plpgsql as $$
begin
  perform private.rpc_fail('KW400','VALIDATION_FAILED','late test failure');
  return new;
end;
$$;
create trigger test_ripening_work_failure before insert on public.ripening_work_results
for each row execute function private.test_ripening_work_failure();
set local role authenticated;
insert into work_responses(name,req) values('late_failure',pg_temp.work_req());
update work_responses set result=public.ripening_ethylene_injection_complete(req)
  where name='late_failure';
select is((select result->'error'->>'code' from work_responses where name='late_failure'),
  'VALIDATION_FAILED','late business error returned in envelope');
select is((select current_weight_kg::numeric from public.containers
  where id='48500000-0000-0000-0000-000000000001'),10::numeric,'late failure restores source weight');
select is((select reserved_weight_kg::numeric from public.containers
  where id='48500000-0000-0000-0000-000000000001'),8::numeric,'late failure restores reservation');
select is((select count(*) from public.inventory_events),0::bigint,'late failure leaves no ledger rows');
select is((select count(*) from public.containers
  where ripening_lot_id='49000000-0000-0000-0000-000000000001'),0::bigint,'late failure leaves no output');
reset role;
select is((select count(*) from public.change_history where entity_type='inventory_event'),
  0::bigint,'late failure leaves no event history');
drop trigger test_ripening_work_failure on public.ripening_work_results;
drop function private.test_ripening_work_failure();
set local role authenticated;
select is(public.ripening_ethylene_injection_complete(
  (select req from work_responses where name='late_failure'))->>'idempotent_replay',
  'true','stored business failure is replayed without writing after cause removed');
insert into work_responses(name,req) values('inject',pg_temp.work_req('{"location_id":"44000000-0000-0000-0000-000000000002"}'));
update work_responses set result=public.ripening_ethylene_injection_complete(req) where name='inject';
select is((select result->>'ok' from work_responses where name='inject'),'true','injection succeeds');
select is((select count(*) from public.work_tasks where status='pending'
  and task_details->>'location'='実績追熟庫'),2::bigint,'both downstream tasks use actual injection location');
select ok((select bool_and(t.version>i.version and t.scheduled_at=t.due_at
    and t.due_at is distinct from i.due_at
    and t.task_details-'location'=i.task_details-'location')
  from public.work_tasks t join initial_tasks i using(id) where t.status='pending'),
  'actual injection recalculates downstream dates while preserving other task details');
select is((select storage_location_id from public.ripening_lots
  where id='49000000-0000-0000-0000-000000000001'),
  '44000000-0000-0000-0000-000000000001'::uuid,'planned location remains unchanged');
reset role;
select is((select count(*) from private.calendar_sync_jobs j join public.work_tasks t on t.id=j.task_id
  where t.status='pending' and j.revision=t.version),2::bigint,'location changes queue both calendar revisions');
select is((select count(*) from public.change_history h join public.work_tasks t on t.id=h.entity_id
  where h.entity_type='work_task' and t.status='pending'
    and h.correlation_id=(select (req->'meta'->>'correlation_id')::uuid from work_responses where name='inject')
    and h.before_data->'task_details'->>'location'='S2冷蔵庫'
    and h.after_data->'task_details'->>'location'='実績追熟庫'),
  2::bigint,'downstream location changes have correlated before and after history');
set local role authenticated;
select is((select current_weight_kg::numeric from public.containers
  where id='48500000-0000-0000-0000-000000000001'),2::numeric,'partial source remains under same ID');
select is((select reserved_weight_kg::numeric from public.containers
  where id='48500000-0000-0000-0000-000000000001'),0::numeric,'consumed reservation released from aggregate');
select is((select status from public.inventory_reservations
  where id='49200000-0000-0000-0000-000000000001'),'consumed','reservation preserved as consumed');
select is((select current_weight_kg::numeric from public.containers
  where ripening_lot_id='49000000-0000-0000-0000-000000000001'),8::numeric,'output has exact ripening weight');
select is((select sum(quantity_delta_kg) from public.inventory_events),0::numeric,'source/output events conserve total');
select is((select status from public.orders where id='47000000-0000-0000-0000-000000000001'),
  'in_progress','confirmed order advances to in progress');
select is((select planned_ethylene_at from public.ripening_lots
  where id='49000000-0000-0000-0000-000000000001'),'2027-06-10 09:00+09'::timestamptz,
  'planned injection preserved');
select ok((select actual_at between statement_timestamp()-interval '1 minute' and statement_timestamp()
  from public.ripening_work_results where work_type='ethylene_injection'),'omitted actual defaults to current time');
select is(public.ripening_ethylene_injection_complete((select req from work_responses where name='inject'))
  ->>'idempotent_replay','true','injection replay succeeds without duplicate writes');
select is((select count(*) from public.inventory_events),2::bigint,'replay does not duplicate inventory events');
select ok((select bool_and(t.version=(i->>'version')::bigint)
  from public.work_tasks t join jsonb_array_elements((select result->'data'->'tasks' from work_responses where name='inject')) i
  on t.id=(i->>'id')::uuid where t.status='pending'),
  'injection replay does not bump downstream revisions');
select is(public.ripening_ethylene_injection_complete(
  jsonb_set((select req from work_responses where name='inject'),'{input,actual_temperature}','21'))
  ->'error'->>'code','IDEMPOTENCY_KEY_REUSED','same operation with changed input rejected');
select is(public.ripening_ethylene_injection_complete(pg_temp.work_req())->'error'->>'code',
  'INVALID_WORK_STATE','new operation cannot re-inject');
select is(public.ripening_ripeness_complete(pg_temp.work_req())->'error'->>'code',
  'INVALID_WORK_STATE','cannot skip removal');

insert into work_responses(name,req) values('remove',pg_temp.work_req(jsonb_build_object(
  'actual_at',to_char((statement_timestamp()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'rest_temperature',18,'location_id','44000000-0000-0000-0000-000000000003')));
update work_responses set result=public.ripening_ethylene_removal_complete(req) where name='remove';
select is((select result->>'ok' from work_responses where name='remove'),'true','removal and resting succeed together');
select is((select task_details->>'location' from public.work_tasks where task_type='ripeness_check'),
  '実績寝かせ庫','ripeness task follows actual resting location');
select ok((select t.version=i.version+1 and t.task_details=i.task_details
  from public.work_tasks t join initial_tasks i using(id) where t.task_type='ethylene_injection'),
  'later location change preserves completed injection task');
reset role;
select is((select count(*) from private.calendar_sync_jobs j join public.work_tasks t on t.id=j.task_id
  where t.task_type='ripeness_check' and j.revision=t.version),1::bigint,
  'resting location queues latest ripeness calendar revision');
set local role authenticated;
select is((select status from public.containers where ripening_lot_id='49000000-0000-0000-0000-000000000001'),
  'resting','physical stage resting');
select ok((select rest_started_at=actual_at from public.ripening_work_results
  where work_type='ethylene_removal_check'),'resting starts at removal actual by default');
select is(public.ripening_ethylene_removal_complete((select req from work_responses where name='remove'))
  ->>'idempotent_replay','true','removal replay is idempotent');
select is(public.ripening_ripeness_complete(pg_temp.work_req())->'error'->>'code',
  'VALIDATION_FAILED','actual before preceding stage rejected');
insert into work_responses(name,req) values('ripe',pg_temp.work_req(jsonb_build_object(
  'actual_at',to_char((statement_timestamp()+interval '2 hours') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))));
update work_responses set result=public.ripening_ripeness_complete(req) where name='ripe';
select is((select result->>'ok' from work_responses where name='ripe'),'true','ripeness completes');
select is((select status from public.containers where ripening_lot_id='49000000-0000-0000-0000-000000000001'),
  'shippable','physical stage becomes shippable');
select is((select status from public.ripening_lots where id='49000000-0000-0000-0000-000000000001'),
  'completed','plan becomes completed');
select is(public.ripening_ripeness_complete((select req from work_responses where name='ripe'))
  ->>'idempotent_replay','true','ripeness replay is idempotent');
select is((select count(*) from public.ripening_work_results),3::bigint,'one result per stage');
select is((select count(*) from public.work_tasks where ripening_lot_id='49000000-0000-0000-0000-000000000001'
  and status='completed'),3::bigint,'all three tasks complete');
select is((select count(*) from public.ripening_allocations where ripening_lot_id='49000000-0000-0000-0000-000000000001'),
  2::bigint,'order and reserve rows maintained');
select is((select allocated_weight_kg::numeric from public.ripening_allocations
  where id='49100000-0000-0000-0000-000000000001'),6::numeric,'order allocation unchanged');
select is((select allocated_weight_kg::numeric from public.ripening_allocations
  where id='49100000-0000-0000-0000-000000000002'),2::numeric,'reserve allocation unchanged');
select is(public.ripening_ripeness_complete(pg_temp.work_req())->'error'->>'code',
  'INVALID_WORK_STATE','no repeat ripeness or reprocessing');
reset role;
select is((select count(*) from private.calendar_sync_jobs j join public.work_tasks t on t.id=j.task_id
  where t.ripening_lot_id='49000000-0000-0000-0000-000000000001' and j.revision=t.version),
  3::bigint,'task completion queues current calendar revision');
select * from finish();
rollback;
