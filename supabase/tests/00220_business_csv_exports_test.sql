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



update public.customers set name=E'=SUM(1,2)"\n顧客',nickname='CSV66_%' where id='45000000-0000-0000-0000-000000000001';
update public.orders set notes=E'@危険"\r\n改行' where id='47000000-0000-0000-0000-000000000001';
insert into public.ripening_lots(id,display_id,variety_id,grade_id,total_weight_kg,storage_location_id,
  planned_ethylene_at,planned_completion_at,assigned_worker_id,harvest_year,harvest_month,master_snapshot)
values('66000000-0000-4000-8000-000000000001','CSV66-追熟','42000000-0000-0000-0000-000000000001',
 'a2000000-0000-0000-0000-000000000005',10,'44000000-0000-0000-0000-000000000001',
 '2026-09-12T15:00:00Z','2026-09-20T15:00:00Z','43000000-0000-0000-0000-000000000001',2025,11,'{"ethylene_hours":48}');
insert into public.ripening_work_results(ripening_lot_id,work_type,actual_at,actual_temperature,location_id,
 performed_by,checked,operation_id,created_by,notes)
values('66000000-0000-4000-8000-000000000001','ethylene_injection','2026-09-12T15:00:00Z',-1,
 '44000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000001',true,gen_random_uuid(),
 '41000000-0000-0000-0000-000000000002',E'+実績"\nメモ');
insert into public.containers(id,display_id,ripening_lot_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,shippable_until,best_before_at)
values('66000000-0000-4000-8000-000000000002','CSV66-container','66000000-0000-4000-8000-000000000001',
 '42000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,10,'shippable',now()+interval '365 days',now()+interval '366 days');
insert into public.shipments(id,display_id,order_id,shipped_at,shipped_by,customer_snapshot,shipping_destination_snapshot,
 operation_id,created_by,status,cancelled_at,cancelled_by,cancellation_reason,cancellation_operation_id)
values('66000000-0000-4000-8000-000000000003','CSV66-shipment','47000000-0000-0000-0000-000000000001',
 '2026-09-12T15:00:00Z','43000000-0000-0000-0000-000000000001','{"name":"=出荷時顧客","nickname":"昔の愛称"}',
 '{"address":"出荷時住所"}',gen_random_uuid(),'41000000-0000-0000-0000-000000000002','confirmed',null,null,null,null);
insert into public.shipment_lines(shipment_id,container_id,shipped_weight_kg,created_by)
values('66000000-0000-4000-8000-000000000003','66000000-0000-4000-8000-000000000002',2.50,'41000000-0000-0000-0000-000000000002');
insert into public.inventory_events(container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
 shipment_line_id,operation_id,occurred_at,reason,created_by)
select sl.container_id,'shipment',-sl.shipped_weight_kg,10,10-sl.shipped_weight_kg,sl.id,s.operation_id,s.shipped_at,'合成出荷',s.created_by
from public.shipment_lines sl join public.shipments s on s.id=sl.shipment_id;
update public.shipments set status='cancelled',cancelled_at='2026-09-14T00:00:00Z',
 cancelled_by='41000000-0000-0000-0000-000000000002',cancellation_reason=E'-取消"\n理由',cancellation_operation_id=gen_random_uuid()
where id='66000000-0000-4000-8000-000000000003';
insert into public.inventory_events(container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
 shipment_line_id,reverses_event_id,operation_id,occurred_at,reason,created_by)
select e.container_id,'shipment_cancel',-e.quantity_delta_kg,e.after_weight_kg,e.before_weight_kg,e.shipment_line_id,
 e.id,s.cancellation_operation_id,s.cancelled_at,'合成取消',s.created_by
from public.inventory_events e join public.shipment_lines sl on sl.id=e.shipment_line_id join public.shipments s on s.id=sl.shipment_id
where e.event_type='shipment';
set constraints all immediate;
create function pg_temp.export(dataset text,filters jsonb default '{}') returns jsonb language sql as $$
 select public.csv_export(jsonb_build_object('meta',jsonb_build_object('correlation_id',gen_random_uuid()),
 'input',jsonb_build_object('dataset',dataset,'filters',filters)));
$$;
create temporary table results(name text primary key,data jsonb);
grant all on results to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);

insert into results values('orders',pg_temp.export('orders'));
select is((select data->>'ok' from results where name='orders'),'true','member exports orders');
select is((select (data->'data'->>'row_count')::int from results where name='orders'),1,'one orders row');
select is((select ascii(left(data->'data'->>'csv',1)) from results where name='orders'),65279,'orders BOM');
select is((select right(data->'data'->>'csv',2) from results where name='orders'),E'\r\n','orders CRLF');
select is((select cardinality(string_to_array(split_part(data->'data'->>'csv',E'\r\n',1),',')) from results where name='orders'),17,'orders fixed header columns');
select is((pg_temp.export('orders','{"search":"no match"}')->'data'->>'row_count')::int,0,'orders empty');
select is((pg_temp.export('orders','{"search":"no match"}')->'data'->>'csv'),
 (select split_part(data->'data'->>'csv',E'\r\n',1)||E'\r\n' from results where name='orders'),'orders header only');
select is(pg_temp.export('orders','{"status":"invalid"}')->'error'->>'code','VALIDATION_FAILED','orders invalid status');
select is(pg_temp.export('orders','{"from_date":"2026-09-14","to_date":"2026-09-13"}')->'error'->>'code','VALIDATION_FAILED','orders invalid range');
select is(pg_temp.export('orders','{"from_date":"2026-02-30"}')->'error'->>'code','VALIDATION_FAILED','orders invalid date');
select is(pg_temp.export('orders','{"sql":"select 1"}')->'error'->>'code','VALIDATION_FAILED','orders unknown filter');
select is(pg_temp.export('orders',jsonb_build_object('search',repeat('x',101)))->'error'->>'code','VALIDATION_FAILED','orders search limit');

insert into results values('ripening',pg_temp.export('ripening'));
select is((select data->>'ok' from results where name='ripening'),'true','member exports ripening');
select is((select (data->'data'->>'row_count')::int from results where name='ripening'),1,'one ripening row');
select is((select ascii(left(data->'data'->>'csv',1)) from results where name='ripening'),65279,'ripening BOM');
select is((select right(data->'data'->>'csv',2) from results where name='ripening'),E'\r\n','ripening CRLF');
select is((select cardinality(string_to_array(split_part(data->'data'->>'csv',E'\r\n',1),',')) from results where name='ripening'),37,'ripening fixed header columns');
select ok(position('収穫年' in (select data->'data'->>'csv' from results where name='ripening'))=0,
  'ripening CSV does not expose compatibility harvest year');
select ok(position('harvest_year' in (select data->'data'->>'csv' from results where name='ripening'))=0,
  'ripening snapshot does not expose compatibility harvest year');
select is((pg_temp.export('ripening','{"search":"no match"}')->'data'->>'row_count')::int,0,'ripening empty');
select is((pg_temp.export('ripening','{"search":"no match"}')->'data'->>'csv'),
 (select split_part(data->'data'->>'csv',E'\r\n',1)||E'\r\n' from results where name='ripening'),'ripening header only');
select is(pg_temp.export('ripening','{"status":"invalid"}')->'error'->>'code','VALIDATION_FAILED','ripening invalid status');
select is(pg_temp.export('ripening','{"from_date":"2026-09-14","to_date":"2026-09-13"}')->'error'->>'code','VALIDATION_FAILED','ripening invalid range');
select is(pg_temp.export('ripening','{"from_date":"2026-02-30"}')->'error'->>'code','VALIDATION_FAILED','ripening invalid date');
select is(pg_temp.export('ripening','{"sql":"select 1"}')->'error'->>'code','VALIDATION_FAILED','ripening unknown filter');
select is(pg_temp.export('ripening',jsonb_build_object('search',repeat('x',101)))->'error'->>'code','VALIDATION_FAILED','ripening search limit');

insert into results values('shipments',pg_temp.export('shipments'));
select is((select data->>'ok' from results where name='shipments'),'true','member exports shipments');
select is((select (data->'data'->>'row_count')::int from results where name='shipments'),1,'one shipments row');
select is((select ascii(left(data->'data'->>'csv',1)) from results where name='shipments'),65279,'shipments BOM');
select is((select right(data->'data'->>'csv',2) from results where name='shipments'),E'\r\n','shipments CRLF');
select is((select cardinality(string_to_array(split_part(data->'data'->>'csv',E'\r\n',1),',')) from results where name='shipments'),20,'shipments fixed header columns');
select is((pg_temp.export('shipments','{"search":"no match"}')->'data'->>'row_count')::int,0,'shipments empty');
select is((pg_temp.export('shipments','{"search":"no match"}')->'data'->>'csv'),
 (select split_part(data->'data'->>'csv',E'\r\n',1)||E'\r\n' from results where name='shipments'),'shipments header only');
select is(pg_temp.export('shipments','{"status":"invalid"}')->'error'->>'code','VALIDATION_FAILED','shipments invalid status');
select is(pg_temp.export('shipments','{"from_date":"2026-09-14","to_date":"2026-09-13"}')->'error'->>'code','VALIDATION_FAILED','shipments invalid range');
select is(pg_temp.export('shipments','{"from_date":"2026-02-30"}')->'error'->>'code','VALIDATION_FAILED','shipments invalid date');
select is(pg_temp.export('shipments','{"sql":"select 1"}')->'error'->>'code','VALIDATION_FAILED','shipments unknown filter');
select is(pg_temp.export('shipments',jsonb_build_object('search',repeat('x',101)))->'error'->>'code','VALIDATION_FAILED','shipments search limit');

select is((pg_temp.export('orders','{"status":"active","search":"csv66_%"}')->'data'->>'row_count')::int,1,'order search matches screen literal case-insensitively');
select is((pg_temp.export('orders','{"search":"csv66_X%"}')->'data'->>'row_count')::int,0,'wildcards are literal');
select is((pg_temp.export('orders','{"status":"shipped"}')->'data'->>'row_count')::int,0,'order status applied');
select is((pg_temp.export('orders','{"from_date":"2027-06-20","to_date":"2027-06-20"}')->'data'->>'row_count')::int,1,'order shipping date inclusive');
select is((pg_temp.export('orders','{"to_date":"2027-06-19"}')->'data'->>'row_count')::int,0,'order excludes date outside range');
select ok(position(E'"''=SUM(1,2)""\n顧客"' in (select data->'data'->>'csv' from results where name='orders'))>0,'order escapes dangerous quoted multiline customer');
select ok(position(E'"''@危険""\r\n改行"' in (select data->'data'->>'csv' from results where name='orders'))>0,'order protects notes');
select ok(position('"11","S2ヘイワード"' in (select data->'data'->>'csv' from results where name='ripening'))>0,'harvest month retained without year');
select ok(position('"2026-09-13T00:00:00.000+09:00","-1"' in (select data->'data'->>'csv' from results where name='ripening'))>0,'actual time in JST and negative numeric not prefixed');
select is((pg_temp.export('ripening','{"from_date":"2026-09-13","to_date":"2026-09-13","search":"CSV66"}')->'data'->>'row_count')::int,1,'ripening JST boundary and search');
select is((pg_temp.export('ripening','{"to_date":"2026-09-12"}')->'data'->>'row_count')::int,0,'ripening previous JST date excluded');
select is((pg_temp.export('shipments','{"from_date":"2026-09-13","to_date":"2026-09-13","status":"cancelled","search":"昔の愛称"}')->'data'->>'row_count')::int,1,'shipment filters use snapshot and JST actual date');
select is((pg_temp.export('shipments','{"status":"confirmed"}')->'data'->>'row_count')::int,0,'cancelled excluded when confirmed requested');
select is((pg_temp.export('shipments','{"order_id":"66000000-0000-4000-8000-000000000009"}')->'data'->>'row_count')::int,0,'selected order isolated');
select is(pg_temp.export('shipments','{"order_id":"bad"}')->'error'->>'code','VALIDATION_FAILED','invalid selected order');
select ok(position('出荷時住所' in (select data->'data'->>'csv' from results where name='shipments'))>0,'shipping destination snapshot');
select ok(position('"2.50"' in (select data->'data'->>'csv' from results where name='shipments'))>0,'line weight fixed decimals');
select throws_ok($$insert into public.csv_export_audits(dataset) values('orders')$$,'42501',null,'audit direct insert denied');
select is((select count(*) from public.csv_export_audits),0::bigint,'member cannot read audits');
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
select is(pg_temp.export('orders')->'error'->>'code','AUTH_FORBIDDEN','pending denied orders');
select is(pg_temp.export('ripening')->'error'->>'code','AUTH_FORBIDDEN','pending denied ripening');
select is(pg_temp.export('shipments')->'error'->>'code','AUTH_FORBIDDEN','pending denied shipments');
select set_config('request.jwt.claim.sub','',true);
select is(pg_temp.export('orders')->'error'->>'code','AUTH_REQUIRED','anonymous JWT rejected');
reset role;
select ok((select bool_and(exported_by='41000000-0000-0000-0000-000000000002') from public.csv_export_audits),'audit actor uses authenticated identity');
select ok((select count(*)>0 from public.csv_export_audits where result_code='VALIDATION_FAILED'),'validation failures audited');
select is((select count(*) from public.inventory_events),2::bigint,'exports create no inventory movements');
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
select pg_temp.export('orders','{"search":"  CSV66_%  "}');
reset role;
select ok(exists(select 1 from public.csv_export_audits where filters='{"search":"CSV66_%","status":"all"}'),'normalized effective filters audited');
-- Row cap and size cap must refuse the whole export, with count recorded.
insert into public.orders(order_number,customer_id,shipping_destination_id,ordered_on,scheduled_ship_on,
 variety_id,grade_id,ordered_weight_kg,shipping_destination_snapshot)
select 'CSV66-LIMIT-'||lpad(n::text,5,'0'),customer_id,shipping_destination_id,ordered_on,scheduled_ship_on,
 variety_id,grade_id,ordered_weight_kg,shipping_destination_snapshot from public.orders cross join generate_series(1,10001) n
where id='47000000-0000-0000-0000-000000000001';
set local role authenticated;
select is((pg_temp.export('orders','{"search":"CSV66-LIMIT-0"}')->'data'->>'row_count')::int,9999,'all matching rows beyond PostgREST 1000 cap');
select is(pg_temp.export('orders','{"search":"CSV66-LIMIT-"}')->'error'->>'code','EXPORT_LIMIT_EXCEEDED','10001 rows rejected');
reset role;
select ok(exists(select 1 from public.csv_export_audits where result_code='EXPORT_LIMIT_EXCEEDED' and row_count=10001),'row limit audit');
update public.orders set notes=repeat('x',10485761) where id='47000000-0000-0000-0000-000000000001';
set local role authenticated;
select is(pg_temp.export('orders','{"search":"ORD-S2-001"}')->'error'->>'code','EXPORT_LIMIT_EXCEEDED','byte limit rejects whole CSV');
reset role;
select * from finish();
rollback;
