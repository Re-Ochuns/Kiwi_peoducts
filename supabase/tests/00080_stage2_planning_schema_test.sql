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
  ('44000000-0000-0000-0000-000000000001', 'S2-COLD', 'S2冷蔵庫', 'cold_storage');

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
  planned_ethylene_at, planned_completion_at, master_snapshot, assigned_worker_id
)
values (
  '49000000-0000-0000-0000-000000000001', '追熟-2027-001',
  '42000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
  10.00, '44000000-0000-0000-0000-000000000001', '2027-06-10 09:00+09',
  '2027-06-20 09:00+09', '{"ethylene_hours":72,"rest_days":7}',
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

insert into public.ripening_lots (
  id, display_id, variety_id, grade_id, total_weight_kg, storage_location_id,
  planned_ethylene_at, planned_completion_at, assigned_worker_id
)
values (
  '49000000-0000-0000-0000-000000000002', '追熟-2027-002',
  '42000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
  1.00, '44000000-0000-0000-0000-000000000001', '2027-06-11 09:00+09',
  '2027-06-21 09:00+09', '43000000-0000-0000-0000-000000000001'
);
insert into public.ripening_allocations (
  ripening_lot_id, allocation_type, allocated_weight_kg
)
values ('49000000-0000-0000-0000-000000000002', 'reserve', 1.00);

select throws_ok(
  $$insert into public.inventory_reservations (ripening_lot_id, container_id, reserved_weight_kg)
    values ('49000000-0000-0000-0000-000000000002', '48500000-0000-0000-0000-000000000001', 1.00)$$,
  '23514', 'reservation exceeds available container weight',
  'over-reservation is rejected'
);

select lives_ok(
  $$update public.ripening_lots set status = 'confirmed'
    where id = '49000000-0000-0000-0000-000000000001'$$,
  'matching allocations and reservations allow confirmation'
);

select throws_ok(
  $$update public.inventory_reservations set reserved_weight_kg = 9.99
    where id = '49200000-0000-0000-0000-000000000001'$$,
  '23514', 'reservation weight can only be changed while lot is draft',
  'confirmed reservation weight is immutable'
);

select is(
  (select reserved_weight_kg::numeric from public.containers where id = '48500000-0000-0000-0000-000000000001'),
  10.00::numeric,
  'rejected reservation change keeps the container total consistent'
);

select throws_ok(
  $$insert into public.ripening_allocations (ripening_lot_id, allocation_type, allocated_weight_kg)
    values ('49000000-0000-0000-0000-000000000001', 'reserve', 0.01)$$,
  '23514', 'ripening allocations can only change while lot is draft',
  'confirmed allocation breakdown is immutable'
);

select throws_ok(
  $$update public.ripening_lots set status = 'confirmed'
    where id = '49000000-0000-0000-0000-000000000002'$$,
  '23514', 'active reservation total must equal lot weight',
  'confirmation requires reservation total to match lot weight'
);

select throws_ok(
  $$insert into public.ripening_allocations (ripening_lot_id, allocation_type, allocated_weight_kg)
    values ('49000000-0000-0000-0000-000000000002', 'reserve', 0.01)$$,
  '23514', 'ripening allocation exceeds lot weight',
  'allocation exceeding the ripening lot weight is rejected'
);

insert into public.work_tasks (
  id, task_type, ripening_lot_id, scheduled_at, due_at, assigned_worker_id,
  target_url, calendar_sync_status
)
values (
  '49300000-0000-0000-0000-000000000001', 'ethylene_injection',
  '49000000-0000-0000-0000-000000000001', '2027-06-10 09:00+09', '2027-06-10 10:00+09',
  '43000000-0000-0000-0000-000000000001', '/worker/ripening/49000000-0000-0000-0000-000000000001', 'pending'
);

select throws_ok(
  $$insert into public.work_tasks (
      task_type, order_id, scheduled_at, due_at, target_url, calendar_sync_status
    ) values (
      'ethylene_injection', '47000000-0000-0000-0000-000000000001', now(), now(), '/invalid', 'pending'
    )$$,
  '23514', null,
  'task type must match its single target'
);

select lives_ok(
  $$insert into public.change_history (
      entity_type, entity_id, operation, after_data, reason, changed_by
    ) values (
      'order', '47000000-0000-0000-0000-000000000001', 'create',
      '{"status":"confirmed"}', 'S2 pgTAP fixture', '41000000-0000-0000-0000-000000000003'
    )$$,
  'S2 entity types can be recorded in immutable history'
);

select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('customers', 'shipping_destinations', 'orders', 'ripening_lots', 'ripening_allocations', 'inventory_reservations', 'work_tasks')
     and c.relrowsecurity),
  7::bigint,
  'RLS is enabled on every S2 table'
);

set local role anon;
select throws_ok($$select * from public.customers$$, '42501', null, 'anonymous cannot read customer data');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);
select is((select count(*) from public.customers), 0::bigint, 'pending user reads no customer data');
select is((select count(*) from public.orders), 0::bigint, 'pending user reads no order data');

select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000002', true);
select is((select count(*) from public.customers), 1::bigint, 'active member reads customer data');
select is((select count(*) from public.ripening_lots), 2::bigint, 'active member reads ripening plans');
select throws_ok(
  $$insert into public.customers (customer_code, name, postal_code, address)
    values ('FORBIDDEN', '禁止', '000', '禁止')$$,
  '42501', null,
  'active member cannot mutate S2 tables directly'
);

select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000003', true);
select is((select count(*) from public.work_tasks), 1::bigint, 'active administrator reads work tasks');
reset role;

select * from finish();
rollback;
