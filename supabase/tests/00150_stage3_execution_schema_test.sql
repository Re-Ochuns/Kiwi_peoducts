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

select has_table('public', 'ripening_work_results', 'ripening_work_results exists');
select has_table('public', 'shipments', 'shipments exists');
select has_table('public', 'shipment_lines', 'shipment_lines exists');
select has_table('public', 'inventory_events', 'inventory_events exists');

update public.ripening_lots set status = 'confirmed'
where id = '49000000-0000-0000-0000-000000000001';
insert into public.ripening_work_results (
  id, ripening_lot_id, work_type, actual_at, actual_temperature, location_id,
  performed_by, checked, operation_id, created_by
) values (
  '60000000-0000-0000-0000-000000000001',
  '49000000-0000-0000-0000-000000000001', 'ethylene_injection', now(), 20,
  '44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001',
  true, gen_random_uuid(), '41000000-0000-0000-0000-000000000002'
);
select is((select planned_ethylene_at from public.ripening_lots
  where id = '49000000-0000-0000-0000-000000000001'),
  '2027-06-10 09:00+09'::timestamptz, 'actual injection does not overwrite plan');
select throws_ok($$update public.ripening_work_results set checked = false$$,
  '23514', null, 'unchecked actual result rejected');
select throws_ok($$update public.ripening_work_results
  set actual_temperature = 'NaN', notes = 'correction'$$,
  '23514', null, 'nonfinite temperature rejected');
select throws_ok($$delete from public.ripening_work_results$$,
  '23514', null, 'actual results cannot be erased');
select lives_ok($$update public.ripening_work_results set actual_temperature = 21,
  notes = 'temperature correction', updated_by = '41000000-0000-0000-0000-000000000003'$$,
  'actual correction can be stored with reason');
select is((select count(*) from public.change_history where entity_type = 'ripening_work_result'),
  2::bigint, 'creation and correction retain before/after history');

insert into public.containers (
  id, display_id, ripening_lot_id, variety_id, grade_id, original_weight_kg,
  current_weight_kg, status, shippable_until, best_before_at
) values (
  '61000000-0000-0000-0000-000000000001', '追熟-2027-001-1',
  '49000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 10, 10, 'shippable',
  now() + interval '5 days', now() + interval '7 days'
);
select is((select status from public.ripening_lots
  where id = '49000000-0000-0000-0000-000000000001'), 'confirmed',
  'physical container stage is independent of planning state');
select throws_ok($$update public.containers set sorting_result_id =
  '48400000-0000-0000-0000-000000000001' where id = '61000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'cannot move ripening output into finalized sorting');
select throws_ok($$update public.containers set shippable_until = best_before_at + interval '1 day'
  where id = '61000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'shipping cutoff cannot exceed best-before');

create function pg_temp.make_shipment(weight numeric) returns uuid
language plpgsql as $$
declare
  shipment_id_value uuid := gen_random_uuid();
  line_id uuid := gen_random_uuid();
  current_weight numeric;
begin
  insert into public.shipments (
    id, display_id, order_id, shipped_at, shipped_by, customer_snapshot,
    shipping_destination_snapshot, operation_id, created_by
  ) values (
    shipment_id_value, '出荷-' || shipment_id_value,
    '47000000-0000-0000-0000-000000000001', now(),
    '43000000-0000-0000-0000-000000000001', '{"name":"S3顧客"}',
    '{"address":"S3配送先"}', gen_random_uuid(), '41000000-0000-0000-0000-000000000002'
  );
  insert into public.shipment_lines (id, shipment_id, container_id, shipped_weight_kg, created_by)
  values (line_id, shipment_id_value, '61000000-0000-0000-0000-000000000001',
    weight, '41000000-0000-0000-0000-000000000002');
  select current_weight_kg into current_weight from public.containers
    where id = '61000000-0000-0000-0000-000000000001';
  insert into public.inventory_events (
    container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
    shipment_line_id, operation_id, occurred_at, reason, created_by
  ) values (
    '61000000-0000-0000-0000-000000000001', 'shipment', -weight,
    current_weight, current_weight - weight, line_id, gen_random_uuid(), now(), '出荷確定',
    '41000000-0000-0000-0000-000000000002'
  );
  return shipment_id_value;
end;
$$;
create function pg_temp.cancel_shipment(target uuid) returns void
language plpgsql as $$
declare e public.inventory_events%rowtype; balance numeric;
begin
  update public.shipments set status = 'cancelled', cancelled_at = now(),
    cancelled_by = '41000000-0000-0000-0000-000000000003',
    cancellation_reason = '入力誤り', cancellation_operation_id = gen_random_uuid()
  where id = target;
  for e in select ev.* from public.inventory_events ev
    join public.shipment_lines l on l.id = ev.shipment_line_id
    where l.shipment_id = target and ev.event_type = 'shipment'
  loop
    select current_weight_kg into balance from public.containers where id = e.container_id;
    insert into public.inventory_events (
      container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
      shipment_line_id, reverses_event_id, operation_id, occurred_at, reason, created_by
    ) values (e.container_id, 'shipment_cancel', -e.quantity_delta_kg, balance,
      balance - e.quantity_delta_kg, e.shipment_line_id, e.id, gen_random_uuid(),
      now(), '出荷取消', '41000000-0000-0000-0000-000000000003');
  end loop;
end;
$$;
create temporary table saved_shipments as select pg_temp.make_shipment(2.25) id;
set constraints all immediate;
set constraints all deferred;
select is((select current_weight_kg::numeric from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 7.75,
  'partial shipment preserves same container ID and residual weight');
select is((select sum(quantity_delta_kg) from public.inventory_events), -2.25,
  'inventory ledger explains decrease');
select throws_ok($$select pg_temp.make_shipment(4)$$, '23514',
  'shipment exceeds ordered weight', 'multiple shipments cannot exceed order');
select throws_ok($$select pg_temp.make_shipment(0.001)$$, '23514', null,
  'shipment precision is 0.01kg');
select throws_ok($$update public.inventory_events set reason = 'rewrite'$$,
  '23514', null, 'inventory events are append-only');
select throws_ok($$delete from public.shipment_lines$$, '23514', null,
  'shipment lines cannot be removed');

select lives_ok($$select pg_temp.cancel_shipment(id) from saved_shipments$$,
  'cancellation restores stock through inverse event');
set constraints all immediate;
set constraints all deferred;
select is((select current_weight_kg::numeric from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 10::numeric,
  'cancellation restores original balance');
select is((select sum(quantity_delta_kg) from public.inventory_events), 0::numeric,
  'original and inverse events net to zero');
select throws_ok($$select pg_temp.cancel_shipment(id) from saved_shipments$$,
  '23514', null, 'cancellation cannot be repeated');
select is((select count(*) from public.change_history where entity_type = 'inventory_event'),
  2::bigint, 'both stock movements have audit records');

update public.containers set shippable_until = now() - interval '1 hour'
  where id = '61000000-0000-0000-0000-000000000001';
select throws_ok($$select pg_temp.make_shipment(1)$$, '23514',
  'container is not available for shipment', 'shipping cutoff enforced before expiry job');
update public.containers set shippable_until = now() - interval '2 days',
  best_before_at = now() - interval '1 day'
  where id = '61000000-0000-0000-0000-000000000001';
select throws_ok($$select pg_temp.make_shipment(1)$$, '23514',
  'container is not available for shipment', 'best-before rejects shipment without disposal');
select is((select current_weight_kg::numeric from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 10::numeric,
  'expiry does not dispose physical stock');

select throws_ok($$insert into public.inventory_events (
  container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
  operation_id, occurred_at, reason, created_by) values (
  '61000000-0000-0000-0000-000000000001', 'adjustment', -1, 9, 8,
  gen_random_uuid(), now(), 'stale write', '41000000-0000-0000-0000-000000000003')$$,
  '23514', 'inventory event balance is stale', 'stale balance cannot overwrite concurrent change');

select throws_ok($$insert into public.ripening_work_results (
  ripening_lot_id, work_type, actual_at, actual_temperature, location_id, performed_by,
  checked, operation_id, created_by) values (
  '49000000-0000-0000-0000-000000000001', 'ripeness_check', now(), 20,
  '44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001',
  true, gen_random_uuid(), '41000000-0000-0000-0000-000000000002')$$,
  '23514', 'ripeness check requires earlier resting start', 'cannot skip removal and resting');
select throws_ok($$insert into public.ripening_work_results (
  ripening_lot_id, work_type, actual_at, actual_temperature, location_id, performed_by,
  checked, operation_id, created_by) values (
  '49000000-0000-0000-0000-000000000001', 'ethylene_injection', now(), 20,
  '44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001',
  true, gen_random_uuid(), '41000000-0000-0000-0000-000000000002')$$,
  '23505', null, 'one actual result per stage');
select throws_ok($$insert into public.containers (
  display_id, ripening_lot_id, variety_id, grade_id, original_weight_kg, current_weight_kg
) values ('extra-output', '49000000-0000-0000-0000-000000000001',
  '42000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005', 1, 1)$$,
  '23514', 'ripening containers exceed planned weight', 'cannot mint excess ripening output');

create function pg_temp.incomplete_shipment() returns void language plpgsql as $$
begin
  insert into public.shipments (
    display_id, order_id, shipped_at, shipped_by, customer_snapshot,
    shipping_destination_snapshot, operation_id, created_by
  ) values ('incomplete', '47000000-0000-0000-0000-000000000001', now(),
    '43000000-0000-0000-0000-000000000001', '{"name":"S3"}', '{"address":"S3"}',
    gen_random_uuid(), '41000000-0000-0000-0000-000000000002');
  set constraints all immediate;
end;
$$;
select throws_ok('select pg_temp.incomplete_shipment()', '23514', 'shipment must contain lines',
  'header without details cannot commit');

-- Deplete the same container, then cancel after the best-before cutoff.
update public.orders set ordered_weight_kg = 10 where id = '47000000-0000-0000-0000-000000000001';
update public.containers set shippable_until = now() + interval '5 days',
  best_before_at = now() + interval '7 days'
  where id = '61000000-0000-0000-0000-000000000001';
create temporary table full_shipment as select pg_temp.make_shipment(10) id;
select is((select status from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 'shipped', 'zero balance is shipped');
update public.containers set shippable_until = now() - interval '2 days',
  best_before_at = now() - interval '1 day'
  where id = '61000000-0000-0000-0000-000000000001';
select lives_ok('select pg_temp.cancel_shipment(id) from full_shipment',
  'full shipment cancellation supports reverse state transition');
set constraints all immediate;
set constraints all deferred;
select is((select status from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 'expired',
  'expired stock restored without making it shippable');
select is((select current_weight_kg::numeric from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 10::numeric,
  'full shipment reversal restores same container balance');
select ok((select expired_at is not null from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 'expiry timestamp retained');
select is((select count(*) from public.change_history
  where entity_type = 'container' and entity_id = '61000000-0000-0000-0000-000000000001'),
  4::bigint, 'container detail history includes all stock movements');
insert into public.inventory_events (
  container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
  operation_id, occurred_at, reason, created_by
) values (
  '61000000-0000-0000-0000-000000000001', 'adjustment', -1, 10, 9,
  '62000000-0000-0000-0000-000000000001', now(), '管理者在庫訂正',
  '41000000-0000-0000-0000-000000000003'
);
select throws_ok($$insert into public.inventory_events (
  container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
  operation_id, occurred_at, reason, created_by
) values (
  '61000000-0000-0000-0000-000000000001', 'adjustment', -1, 9, 8,
  '62000000-0000-0000-0000-000000000001', now(), '重複送信',
  '41000000-0000-0000-0000-000000000003'
)$$, '23505', null, 'duplicate operation cannot create a second event');
select is((select current_weight_kg::numeric from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 9::numeric,
  'duplicate event failure rolls back balance and history side effects');
select ok(not has_table_privilege('anon', 'public.' || name, 'SELECT'),
  'anonymous cannot read ' || name)
from unnest(array['ripening_work_results','shipments','shipment_lines','inventory_events']) names(name);
select ok(not has_table_privilege('authenticated', 'public.' || name, 'INSERT,UPDATE,DELETE'),
  'authenticated role cannot directly mutate ' || name)
from unnest(array['ripening_work_results','shipments','shipment_lines','inventory_events']) names(name);
-- Conflict-skipped inserts must have no stock or audit side effects.
insert into public.inventory_events (
  container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
  operation_id, occurred_at, reason, created_by
) values (
  '61000000-0000-0000-0000-000000000001', 'adjustment', -1, 9, 8,
  '62000000-0000-0000-0000-000000000001', now(), 'duplicate ignored',
  '41000000-0000-0000-0000-000000000003'
) on conflict (operation_id, container_id, event_type) do nothing;
select is((select current_weight_kg::numeric from public.containers
  where id = '61000000-0000-0000-0000-000000000001'), 9::numeric,
  'conflict-skipped event does not change balance');
select is((select count(*) from public.inventory_events
  where container_id = '61000000-0000-0000-0000-000000000001'), 5::bigint,
  'conflict-skipped event does not add a ledger row');
select is((select count(*) from public.change_history where entity_type = 'container'
  and entity_id = '61000000-0000-0000-0000-000000000001'), 5::bigint,
  'conflict-skipped event does not add phantom container history');

insert into public.ripening_work_results (
  ripening_lot_id, work_type, actual_at, actual_temperature, location_id,
  performed_by, checked, operation_id, created_by, rest_started_at, rest_temperature
) values (
  '49000000-0000-0000-0000-000000000001', 'ethylene_removal_check', now(), 20,
  '44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001',
  true, gen_random_uuid(), '41000000-0000-0000-0000-000000000002', now(), 18
);
select throws_ok($$update public.ripening_work_results
  set actual_temperature = 99, notes = 'late correction'
  where work_type = 'ethylene_injection'$$, '23514',
  'ripening result cannot be corrected after next stage started',
  'injection correction rejected after removal started');
select lives_ok($$update public.ripening_work_results
  set rest_temperature = 19, notes = 'before next stage'
  where work_type = 'ethylene_removal_check'$$,
  'removal correction allowed before ripeness check');
insert into public.ripening_work_results (
  ripening_lot_id, work_type, actual_at, actual_temperature, location_id,
  performed_by, checked, operation_id, created_by
) values (
  '49000000-0000-0000-0000-000000000001', 'ripeness_check', now(), 20,
  '44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001',
  true, gen_random_uuid(), '41000000-0000-0000-0000-000000000002'
);
select throws_ok($$update public.ripening_work_results
  set rest_temperature = 99, notes = 'late correction'
  where work_type = 'ethylene_removal_check'$$, '23514',
  'ripening result cannot be corrected after next stage started',
  'removal correction rejected after ripeness check');
select throws_ok($$update public.ripening_work_results
  set actual_temperature = 99, notes = 'after shipment'
  where work_type = 'ripeness_check'$$, '23514',
  'ripening result cannot be corrected after next stage started',
  'ripeness correction rejected when shipment history exists');
set local role anon;
select throws_ok('select * from public.shipments', '42501', null, 'anonymous read denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);
select is((select count(*) from public.shipments), 0::bigint, 'pending user sees no shipments');
select is((select count(*) from public.inventory_events), 0::bigint, 'pending user sees no stock events');
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000002', true);
select is((select count(*) from public.shipments), 2::bigint, 'active member reads shipments');
select is((select count(*) from public.ripening_work_results), 3::bigint, 'active member reads actual results');
select throws_ok('delete from public.inventory_events', '42501', null, 'member cannot mutate ledger');
select throws_ok('update public.shipments set status = ''cancelled''', '42501', null, 'member must use RPC');
select set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000003', true);
select throws_ok('delete from public.ripening_work_results', '42501', null, 'administrator cannot bypass RPC');
reset role;
select * from finish();
rollback;
