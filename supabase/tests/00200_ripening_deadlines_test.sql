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


create function pg_temp.req(input jsonb) returns jsonb language sql as $$
  select jsonb_build_object('meta',jsonb_build_object('idempotency_key',gen_random_uuid(),'correlation_id',gen_random_uuid()),'input',input);
$$;
create temporary table results (name text primary key, req jsonb, data jsonb);
grant all on results to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
insert into results(name,req) values('master',pg_temp.req('{
  "master_type":"ripening_rule","harvest_month":5,
  "variety_id":"42000000-0000-0000-0000-000000000001","ethylene_temperature":20,
  "ethylene_hours":48,"rest_temperature":15,"rest_days":3,"shippable_days":5,"best_before_days":7
}'));
update results set data=public.master_register(req) where name='master';
select is((select data->>'ok' from results where name='master'),'true','administrator creates ripening master');
select is(public.master_register((select req from results where name='master'))->>'idempotent_replay','true','master replay');
select is(public.master_register(pg_temp.req((select req->'input' from results where name='master')))->'error'->>'code',
  'MASTER_DUPLICATE','duplicate harvest key rejected');
select is(public.master_register(pg_temp.req((select req->'input'||'{"harvest_month":10,"shippable_days":8}' from results where name='master')))->'error'->>'code',
  'VALIDATION_FAILED','shipping period cannot exceed shelf life');
select is(public.master_register(pg_temp.req((select req->'input'||'{"harvest_month":13}' from results where name='master')))->'error'->>'code',
  'VALIDATION_FAILED','invalid harvest month rejected');
select is(public.master_register(pg_temp.req((select req->'input'||'{"harvest_year":2027}' from results where name='master')))->'error'->>'code',
  'VALIDATION_FAILED','harvest year is not accepted');
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
select is(public.master_register(pg_temp.req((select req->'input'||'{"harvest_month":10}' from results where name='master')))->'error'->>'code',
  'AUTH_FORBIDDEN','member cannot modify master');
select throws_ok($$insert into public.ripening_rules(harvest_year) values(2026)$$,'42501',null,'direct master write denied');
select ok(not has_function_privilege('authenticated','public.ripening_deadlines_process()','EXECUTE'),'members cannot run clock transitions');
select ok(not has_function_privilege('anon','public.ripening_deadlines_process()','EXECUTE'),'anonymous cannot run clock transitions');
select ok(not has_function_privilege('authenticated','private.process_ripening_deadlines(timestamptz)','EXECUTE'),'caller cannot supply arbitrary time');
insert into results(name,req) values('plan',pg_temp.req('{
  "variety_id":"42000000-0000-0000-0000-000000000001",
  "grade_id":"a2000000-0000-0000-0000-000000000005","total_weight_kg":8,
  "storage_location_id":"44000000-0000-0000-0000-000000000001",
  "assigned_worker_id":"43000000-0000-0000-0000-000000000001",
  "planned_ethylene_at":"2030-06-01T09:00:00+09:00","planned_completion_at":"2030-06-20T09:00:00+09:00",
  "allocations":[{"allocation_type":"order","order_id":"47000000-0000-0000-0000-000000000001","allocated_weight_kg":6},
    {"allocation_type":"reserve","allocated_weight_kg":2}],
  "reservations":[{"container_id":"48500000-0000-0000-0000-000000000001","reserved_weight_kg":8}]
}'));
select is(public.ripening_plan_register(pg_temp.req((select req->'input'||'{"harvest_month":5}' from results where name='plan')))->'error'->>'code',
  'VALIDATION_FAILED','client cannot override the inventory harvest month');
update results set data=public.ripening_plan_register(req) where name='plan';
select is((select data->>'ok' from results where name='plan'),'true','plan derives harvest month from inventory');
select is((select data->'data'->>'harvest_month' from results where name='plan'),'5','receiving month is stored on plan');
select is((select data->'data'->'master_snapshot'->>'ethylene_hours' from results where name='plan'),'48','month and variety select the master');
reset role;
select ok(exists(select 1 from public.change_history
  where entity_type='ripening_lot' and entity_id=(select (data->'data'->>'id')::uuid from results where name='plan')
    and reason='品種・収穫月別の追熟条件保存'
    and after_data->'master_snapshot'->>'ethylene_hours'='48'
    and after_data->>'planned_completion_at' is not null),
  'derived master and completion are retained in change history');
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
create function pg_temp.lot_id() returns uuid language sql as $$select (data->'data'->>'id')::uuid from results where name='plan'$$;
select is((select calculated_removal_at from public.ripening_lots where id=pg_temp.lot_id()),'2030-06-03 00:00Z'::timestamptz,'planned removal uses snapshotted duration');
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000003',true);
select is(public.master_update(pg_temp.req((select req->'input'||jsonb_build_object(
  'master_id',data->'data'->>'master_id','expected_version',1,'reason','change master','ethylene_hours',72)
  from results where name='master')))->>'ok','true','master can be changed after plan creation');
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
select is(public.ripening_plan_update(pg_temp.req((select req->'input'||jsonb_build_object(
  'ripening_lot_id',pg_temp.lot_id(),'expected_version',(select version from public.ripening_lots where id=pg_temp.lot_id()),'reason','same harvest replan')
  from results where name='plan')))->>'ok','true','same-source plan update succeeds');
select is((select master_snapshot->>'ethylene_hours' from public.ripening_lots where id=pg_temp.lot_id()),'48','same month update preserves original snapshot');
select is(public.ripening_plan_confirm(pg_temp.req(jsonb_build_object('ripening_lot_id',pg_temp.lot_id(),
  'expected_version',(select version from public.ripening_lots where id=pg_temp.lot_id()),'reason','confirm')))->>'ok','true','confirm plan');
create function pg_temp.work_req(actual text) returns jsonb language sql as $$
  select pg_temp.req(jsonb_build_object('ripening_lot_id',pg_temp.lot_id(),
    'expected_version',(select version from public.ripening_lots where id=pg_temp.lot_id()),
    'location_id','44000000-0000-0000-0000-000000000001','performed_by','43000000-0000-0000-0000-000000000001',
    'checked',true,'actual_at',actual,'actual_temperature',20));
$$;
insert into results(name,req) values('injection',pg_temp.work_req('2030-06-02T09:00:00+09:00'));
update results set data=public.ripening_ethylene_injection_complete(req) where name='injection';
select is((select data->>'ok' from results where name='injection'),'true','injection completes with snapshot');
select is((select calculated_removal_at from public.ripening_lots where id=pg_temp.lot_id()),'2030-06-04 00:00Z'::timestamptz,'actual injection moves removal date');
select is((select calculated_rest_end_at from public.ripening_lots where id=pg_temp.lot_id()),'2030-06-07 00:00Z'::timestamptz,'rest end calculated from actual injection');
select is((select planned_ethylene_at from public.ripening_lots where id=pg_temp.lot_id()),'2030-06-01 00:00Z'::timestamptz,'original planned injection unchanged');
select is((select planned_completion_at from public.ripening_lots where id=pg_temp.lot_id()),'2030-06-06 00:00Z'::timestamptz,'completion plan is calculated from the saved master');
select is((select shippable_until from public.containers where ripening_lot_id=pg_temp.lot_id()),'2030-06-12 00:00Z'::timestamptz,'shipping cutoff uses rest end plus shipping days');
select is((select best_before_at from public.containers where ripening_lot_id=pg_temp.lot_id()),'2030-06-14 00:00Z'::timestamptz,'best-before uses actual schedule');
select is(public.ripening_ethylene_injection_complete((select req from results where name='injection'))->>'idempotent_replay','true','injection replay retains snapshot and dates');
reset role;
select private.process_ripening_deadlines('2030-06-03 23:59:59.999999Z');
select is((select is_overdue from public.work_tasks where ripening_lot_id=pg_temp.lot_id() and task_type='ethylene_removal_check'),false,'not overdue one microsecond before due');
select private.process_ripening_deadlines('2030-06-04 00:00Z');
select is((select is_overdue from public.work_tasks where ripening_lot_id=pg_temp.lot_id() and task_type='ethylene_removal_check'),true,'overdue at exact deadline');
create temporary table history_checkpoint as select count(*) count from public.change_history;
select private.process_ripening_deadlines('2030-06-04 00:00Z');
select is((select count(*) from public.change_history),(select count from history_checkpoint),'deadline replay creates no history');
set local role authenticated;
select is(public.label_mark_handwritten(pg_temp.req(jsonb_build_object(
  'label_job_id',(select j.id from public.label_jobs j join public.containers c on c.id=j.container_id where c.ripening_lot_id=pg_temp.lot_id()),
  'worker_id','43000000-0000-0000-0000-000000000001')))->>'ok','true','complete ripening label before removal');
select is(public.ripening_ethylene_removal_complete(pg_temp.work_req('2030-06-04T09:00:00+09:00')||
  jsonb_build_object('input',(pg_temp.work_req('2030-06-04T09:00:00+09:00')->'input')||'{"rest_temperature":15}'))->>'ok',
  'true','overdue removal task is still completable');
select is((select is_overdue from public.work_tasks where ripening_lot_id=pg_temp.lot_id() and task_type='ethylene_removal_check'),false,'completion clears overdue flag');
reset role;
select private.process_ripening_deadlines('2030-06-06 23:59:59.999999Z');
select is((select status from public.containers where ripening_lot_id=pg_temp.lot_id()),'resting','resting until boundary');
select private.process_ripening_deadlines('2030-06-07 00:00Z');
select is((select status from public.containers where ripening_lot_id=pg_temp.lot_id()),'awaiting_ripeness_check','rest end requests manual check, not automatic shipping');
set local role authenticated;
select is(public.ripening_ripeness_complete(pg_temp.work_req('2030-06-07T09:00:00+09:00'))->>'ok','true','manual ripeness check completes');
select is(jsonb_array_length(public.shipment_container_list('47000000-0000-0000-0000-000000000001')),0,'shipping candidates exclude a future shipping window');
select is(public.shipment_confirm(pg_temp.req(jsonb_build_object(
  'order_id','47000000-0000-0000-0000-000000000001',
  'expected_order_version',(select version from public.orders where id='47000000-0000-0000-0000-000000000001'),
  'worker_id','43000000-0000-0000-0000-000000000001','checked',true,'reason','before shipping window',
  'lines',(select jsonb_build_array(jsonb_build_object('container_id',id,'expected_version',version,'shipped_weight_kg',1))
    from public.containers where ripening_lot_id=pg_temp.lot_id()))))->'error'->>'code',
  'CONTAINER_UNAVAILABLE','manual check does not bypass shipping window start');

reset role;
select private.process_ripening_deadlines('2030-06-11 23:59:59.999999Z');
select is((select needs_review from public.containers where ripening_lot_id=pg_temp.lot_id()),false,'no warning before shipping cutoff');
select private.process_ripening_deadlines('2030-06-12 00:00Z');
select is((select needs_review from public.containers where ripening_lot_id=pg_temp.lot_id()),true,'shipping cutoff marks review');
select is((select status from public.containers where ripening_lot_id=pg_temp.lot_id()),'shippable','shipping cutoff is distinct from best-before expiry');
select ok((select needs_review from public.ripening_lots where id=pg_temp.lot_id()),'related plan needs review');
select ok((select needs_review from public.orders where id='47000000-0000-0000-0000-000000000001'),'related order needs review');
select ok((select needs_review from public.inventory_reservations where ripening_lot_id=pg_temp.lot_id()),'consumed source reservation retains review flag');
select private.process_ripening_deadlines('2030-06-13 23:59:59.999999Z');
select is((select status from public.containers where ripening_lot_id=pg_temp.lot_id()),'shippable','not expired before best-before');
create temporary table event_checkpoint as select count(*) count from public.inventory_events;
select private.process_ripening_deadlines('2030-06-14 00:00Z');
select is((select status from public.containers where ripening_lot_id=pg_temp.lot_id()),'expired','expired at exact best-before');
select is((select current_weight_kg::numeric from public.containers where ripening_lot_id=pg_temp.lot_id()),8::numeric,'expiration does not dispose of physical stock');
select is((select count(*) from public.inventory_events),(select count from event_checkpoint),'expiration does not create inventory movements');
truncate history_checkpoint;
insert into history_checkpoint select count(*) from public.change_history;
select private.process_ripening_deadlines('2030-06-15 00:00Z');
select is((select count(*) from public.change_history),(select count from history_checkpoint),'next-day repeat has no additional updates');
select is((select count(*) from cron.job where jobname='ripening-deadlines'),1::bigint,'one automatic deadline job installed');

select ok((select bool_and(changed_by is null) from public.change_history where reason like '%（自動）'),'automatic changes do not impersonate workers');
select ok((select bool_and(j.revision=t.version) from private.calendar_sync_jobs j join public.work_tasks t on t.id=j.task_id
  where t.ripening_lot_id=pg_temp.lot_id()),'overdue flags enqueue current calendar revisions');

select * from finish();
rollback;
