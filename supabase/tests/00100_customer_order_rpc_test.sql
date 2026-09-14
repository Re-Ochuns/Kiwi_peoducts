begin;
select no_plan();

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('00000000-0000-0000-0000-000000000000','81000000-0000-0000-0000-000000000001',
    'authenticated','authenticated','s2-pending@example.com','',now(),
    '{"provider":"google","providers":["google"]}','{"full_name":"S2 Pending"}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','81000000-0000-0000-0000-000000000002',
    'authenticated','authenticated','s2-member@example.com','',now(),
    '{"provider":"google","providers":["google"]}','{"full_name":"S2 Member"}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','81000000-0000-0000-0000-000000000003',
    'authenticated','authenticated','s2-admin@example.com','',now(),
    '{"provider":"google","providers":["google"]}','{"full_name":"S2 Admin"}',now(),now());
select private.set_user_access('81000000-0000-0000-0000-000000000002','active',array['member']);
select private.set_user_access('81000000-0000-0000-0000-000000000003','active',array['administrator']);

select has_function('public'::name,'customer_register'::name,array['jsonb']::name[],'customer_register exists');
select has_function('public'::name,'shipping_destination_register'::name,array['jsonb']::name[],'destination register exists');
select has_function('public'::name,'order_register'::name,array['jsonb']::name[],'order_register exists');
select has_function('public'::name,'order_update'::name,array['jsonb']::name[],'order_update exists');
select has_function('public'::name,'order_confirm'::name,array['jsonb']::name[],'order_confirm exists');
select has_function('public'::name,'order_cancel'::name,array['jsonb']::name[],'order_cancel exists');
select is_definer('public'::name,'order_register'::name,array['jsonb']::name[],'mutations run as definer');

create function public.test_s2_req(key_value text,corr_value text,input_value jsonb)
returns jsonb language sql as $$
  select jsonb_build_object('meta',jsonb_build_object(
    'idempotency_key',key_value,'correlation_id',corr_value),'input',input_value);
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',true);
select set_config('test.member_denied',public.customer_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001',
  '{"customer_code":"C-MEMBER","name":"不可","postal_code":"000","address":"不可"}'))::text,true);
select is(current_setting('test.member_denied')::jsonb->'error'->>'code','AUTH_FORBIDDEN',
  'member cannot mutate customer data');

select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000003',true);
select set_config('test.customer',public.customer_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000002','83000000-0000-4000-8000-000000000002',
  '{"customer_code":"C-050","name":"テスト顧客","nickname":"テスト","postal_code":"960-0000","address":"福島県"}'))::text,true);
select is(current_setting('test.customer')::jsonb->>'ok','true','administrator registers a customer');
select is(current_setting('test.customer')::jsonb->'data'->>'version','1','customer starts at version one');

select set_config('test.customer_replay',public.customer_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000002','83000000-0000-4000-8000-000000000003',
  '{"customer_code":"C-050","name":"テスト顧客","nickname":"テスト","postal_code":"960-0000","address":"福島県"}'))::text,true);
select is(current_setting('test.customer_replay')::jsonb->>'idempotent_replay','true',
  'customer registration is idempotent');
select is((select count(*) from public.customers where customer_code='C-050'),1::bigint,
  'idempotent replay creates one customer');

select set_config('test.destination1',public.shipping_destination_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000004','83000000-0000-4000-8000-000000000004',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'destination_name','本社','recipient_name','受取 太郎','postal_code','960-0001','address','旧住所')))::text,true);
select set_config('test.destination2',public.shipping_destination_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000005','83000000-0000-4000-8000-000000000005',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'destination_name','支店','recipient_name','受取 花子','postal_code','960-0002','address','支店住所')))::text,true);
select is((select count(*) from public.shipping_destinations
  where customer_id=(current_setting('test.customer')::jsonb->'data'->>'id')::uuid),2::bigint,
  'one customer can have multiple destinations');
select is(jsonb_array_length(public.customer_get(
  (current_setting('test.customer')::jsonb->'data'->>'id')::uuid)->'destinations'),2,
  'customer_get includes destinations');

select set_config('test.customer_updated',public.customer_update(public.test_s2_req(
  '82000000-0000-4000-8000-000000000006','83000000-0000-4000-8000-000000000006',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'expected_version',1,'customer_code','C-050','name','テスト顧客更新',
    'nickname','更新','postal_code','960-0000','address','福島県更新','reason','顧客修正')))::text,true);
select is(current_setting('test.customer_updated')::jsonb->'data'->>'version','2',
  'customer update increments version');
select set_config('test.customer_stale',public.customer_update(public.test_s2_req(
  '82000000-0000-4000-8000-000000000007','83000000-0000-4000-8000-000000000007',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'expected_version',1,'customer_code','C-050','name','競合',
    'postal_code','960-0000','address','競合','reason','古い更新')))::text,true);
select is(current_setting('test.customer_stale')::jsonb->'error'->>'code','CONFLICT_STALE',
  'stale customer update is rejected');

select set_config('test.order_bad_date',public.order_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000008','83000000-0000-4000-8000-000000000008',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'shipping_destination_id',current_setting('test.destination1')::jsonb->'data'->>'id',
    'ordered_date','2027-06-10','scheduled_ship_date','2027-06-09',
    'variety_id',(select id from public.varieties where is_active order by id limit 1),
    'grade_id',(select id from public.grades where code='M'),'ordered_weight_kg',2)))::text,true);
select is(current_setting('test.order_bad_date')::jsonb->'error'->>'code','VALIDATION_FAILED',
  'ship date before order date is rejected');

select set_config('test.order',public.order_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000009','83000000-0000-4000-8000-000000000009',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'shipping_destination_id',current_setting('test.destination1')::jsonb->'data'->>'id',
    'ordered_date','2027-06-10','scheduled_ship_date','2027-06-20',
    'variety_id',(select id from public.varieties where is_active order by id limit 1),
    'grade_id',(select id from public.grades where code='M'),'ordered_weight_kg',2,
    'notes','受注メモ')))::text,true);
select is(current_setting('test.order')::jsonb->'data'->>'status','draft','new order is draft');
select matches(current_setting('test.order')::jsonb->'data'->>'order_number','^受注-2027-[0-9]{3,}$',
  'server issues an immutable order number');
select is(current_setting('test.order')::jsonb->'data'->'shipping_destination_snapshot'->>'address',
  '旧住所','order stores destination snapshot');

select set_config('test.destination_updated',public.shipping_destination_update(public.test_s2_req(
  '82000000-0000-4000-8000-000000000010','83000000-0000-4000-8000-000000000010',
  jsonb_build_object('shipping_destination_id',current_setting('test.destination1')::jsonb->'data'->>'id',
    'expected_version',1,'customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'destination_name','本社','recipient_name','受取 太郎','postal_code','960-0001',
    'address','新住所','reason','移転')))::text,true);
select is(current_setting('test.destination_updated')::jsonb->'data'->>'version','2',
  'destination update increments version');
select is((select shipping_destination_snapshot->>'address' from public.orders
  where id=(current_setting('test.order')::jsonb->'data'->>'id')::uuid),'旧住所',
  'destination update does not rewrite order snapshot');

-- Exercise the migrated legacy order path; new inventory-first orders are covered in 00230.
reset role;
update public.orders set inventory_first=false where id=(current_setting('test.order')::jsonb->'data'->>'id')::uuid;
set local role authenticated;

select set_config('test.confirmed',public.order_confirm(public.test_s2_req(
  '82000000-0000-4000-8000-000000000011','83000000-0000-4000-8000-000000000011',
  jsonb_build_object('order_id',current_setting('test.order')::jsonb->'data'->>'id',
    'expected_version',1,'reason','受注確定')))::text,true);
select is(current_setting('test.confirmed')::jsonb->'data'->>'status','confirmed',
  'draft order can be confirmed');
select is(current_setting('test.confirmed')::jsonb->'data'->>'version','2',
  'confirmation increments version');

reset role;

insert into public.sorting_results(id,display_id,receiving_lot_id,sorted_on,sorted_by,
  input_weight_kg,output_weight_kg,loss_weight_kg)
values('89200000-0000-0000-0000-000000000001','選果-2027-050',
  'aa000000-0000-0000-0000-000000000001','2027-06-11',
  'a7000000-0000-0000-0000-000000000001',2,2,0);
insert into public.containers(id,display_id,sorting_result_id,variety_id,grade_id,
  original_weight_kg,current_weight_kg,status,location_id)
values('89300000-0000-0000-0000-000000000001','選果-2027-050-1',
  '89200000-0000-0000-0000-000000000001',
  (current_setting('test.order')::jsonb->'data'->>'variety_id')::uuid,
  (current_setting('test.order')::jsonb->'data'->>'grade_id')::uuid,
  2,2,'cold_storage','a8000000-0000-0000-0000-000000000001');

insert into public.ripening_lots(id,display_id,variety_id,grade_id,total_weight_kg,
  storage_location_id,planned_ethylene_at,planned_completion_at,assigned_worker_id,
  created_by,updated_by)
select '89000000-0000-0000-0000-000000000001','追熟-2027-050',
  (current_setting('test.order')::jsonb->'data'->>'variety_id')::uuid,
  (current_setting('test.order')::jsonb->'data'->>'grade_id')::uuid,2,
  s.id,'2027-06-12 09:00+09','2027-06-15 09:00+09',w.id,
  '81000000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000003'
from (select id from public.storage_locations where is_active order by id limit 1) s
cross join (select id from public.workers where is_active order by id limit 1) w;
insert into public.ripening_allocations(id,ripening_lot_id,allocation_type,order_id,
  allocated_weight_kg,created_by,updated_by)
values('89100000-0000-0000-0000-000000000001','89000000-0000-0000-0000-000000000001',
  'order',(current_setting('test.order')::jsonb->'data'->>'id')::uuid,2,
  '81000000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000003');
insert into public.inventory_reservations(id,ripening_lot_id,container_id,reserved_weight_kg,
  created_by,updated_by)
values('89400000-0000-0000-0000-000000000001','89000000-0000-0000-0000-000000000001',
  '89300000-0000-0000-0000-000000000001',2,
  '81000000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000003');

update public.ripening_lots set status='confirmed'
where id='89000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000003',true);

select set_config('test.order_updated',public.order_update(public.test_s2_req(
  '82000000-0000-4000-8000-000000000012','83000000-0000-4000-8000-000000000012',
  jsonb_build_object('order_id',current_setting('test.order')::jsonb->'data'->>'id',
    'expected_version',2,'customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'shipping_destination_id',current_setting('test.destination1')::jsonb->'data'->>'id',
    'ordered_date','2027-06-10','scheduled_ship_date','2027-06-21',
    'variety_id',current_setting('test.order')::jsonb->'data'->>'variety_id',
    'grade_id',current_setting('test.order')::jsonb->'data'->>'grade_id',
    'ordered_weight_kg',2,'notes','変更後','reason','出荷予定変更')))::text,true);
select is(current_setting('test.order_updated')::jsonb->'data'->>'status','draft',
  'confirmed order change returns it to draft');
select is((select needs_review from public.ripening_lots
  where id='89000000-0000-0000-0000-000000000001'),true,
  'confirmed order change marks related plan for review');

select is(current_setting('test.order_updated')::jsonb->'data'->'shipping_destination_snapshot'->>'address',
  '旧住所','date and notes updates preserve the original destination snapshot');
select is((select count(*) from public.change_history
  where entity_type='ripening_lot' and correlation_id='83000000-0000-4000-8000-000000000012'),
  1::bigint,'order update audits the related plan');
select is((select before_data->>'needs_review' from public.change_history
  where entity_type='ripening_lot' and correlation_id='83000000-0000-4000-8000-000000000012'),
  'false','plan audit retains the old review flag');
select is((select after_data->>'needs_review' from public.change_history
  where entity_type='ripening_lot' and correlation_id='83000000-0000-4000-8000-000000000012'),
  'true','plan audit retains the new review flag');

select set_config('test.reconfirmed',public.order_confirm(public.test_s2_req(
  '82000000-0000-4000-8000-000000000013','83000000-0000-4000-8000-000000000013',
  jsonb_build_object('order_id',current_setting('test.order')::jsonb->'data'->>'id',
    'expected_version',3,'reason','再確定')))::text,true);
select is(current_setting('test.reconfirmed')::jsonb->'data'->>'status','confirmed',
  'changed order can be reconfirmed');

select is((select operation from public.change_history
  where entity_type='ripening_lot' and correlation_id='83000000-0000-4000-8000-000000000012'),
  'transition','confirmed plan demotion is audited as a transition');
select set_config('test.plan_before_failure',
  (select to_jsonb(l)::text from public.ripening_lots l
   where id='89000000-0000-0000-0000-000000000001'),true);

-- Fail after allocation removal and reservation update, before their audit commits.
reset role;
create function public.test_reject_reservation_audit() returns trigger
language plpgsql as $$
begin
  if new.entity_type='inventory_reservation' then
    raise exception 'injected audit failure';
  end if;
  return new;
end;
$$;
create trigger test_reject_reservation_audit before insert on public.change_history
for each row execute function public.test_reject_reservation_audit();
set local role authenticated;
select throws_ok($cancel$select public.order_cancel(public.test_s2_req(
  '82000000-0000-4000-8000-000000000014','83000000-0000-4000-8000-000000000014',
  jsonb_build_object('order_id',current_setting('test.order')::jsonb->'data'->>'id',
    'expected_version',4,'reason','顧客都合')))$cancel$,
  'P0001','injected audit failure','audit failure aborts the entire cancellation');
select is((select status from public.orders
  where id=(current_setting('test.order')::jsonb->'data'->>'id')::uuid),
  'confirmed','failed cancellation preserves the order');
select is((select count(*) from public.ripening_allocations
  where id='89100000-0000-0000-0000-000000000001'),1::bigint,
  'failed cancellation restores the deleted allocation');
select is((select reserved_weight_kg::numeric from public.containers
  where id='89300000-0000-0000-0000-000000000001'),2::numeric,
  'failed cancellation restores container reserved weight');
select is((select status from public.inventory_reservations
  where id='89400000-0000-0000-0000-000000000001'),'active',
  'failed cancellation restores the reservation');
select is((select to_jsonb(l) from public.ripening_lots l
  where id='89000000-0000-0000-0000-000000000001'),
  current_setting('test.plan_before_failure')::jsonb,
  'failed cancellation restores the full plan including version and totals');
select is((select count(*) from public.change_history
  where correlation_id='83000000-0000-4000-8000-000000000014'),0::bigint,
  'failed cancellation leaves no related audit records');
reset role;
drop trigger test_reject_reservation_audit on public.change_history;
drop function public.test_reject_reservation_audit();
set local role authenticated;
-- Retry the same key after the rolled-back failure.
select set_config('test.cancelled',public.order_cancel(public.test_s2_req(
  '82000000-0000-4000-8000-000000000014','83000000-0000-4000-8000-000000000014',
  jsonb_build_object('order_id',current_setting('test.order')::jsonb->'data'->>'id',
    'expected_version',4,'reason','顧客都合')))::text,true);
select is(current_setting('test.cancelled')::jsonb->'data'->>'status','cancelled',
  'confirmed order can be cancelled before work starts');
select is((select count(*) from public.ripening_allocations
  where order_id=(current_setting('test.order')::jsonb->'data'->>'id')::uuid),0::bigint,
  'cancellation removes order allocations');
select is((select status from public.inventory_reservations
  where id='89400000-0000-0000-0000-000000000001'),'released',
  'cancellation releases the corresponding pre-work reservation');
select is((select reserved_weight_kg::numeric from public.containers
  where id='89300000-0000-0000-0000-000000000001'),0::numeric,
  'reservation release restores available container weight');
select is((select allocated_weight_kg::numeric from public.orders
  where id=(current_setting('test.order')::jsonb->'data'->>'id')::uuid),0::numeric,
  'cancellation updates allocated order weight');
select is((select count(*) from public.order_list('cancelled','受注-2027-')),1::bigint,
  'order_list supports status and literal search');
select is(public.order_get((current_setting('test.order')::jsonb->'data'->>'id')::uuid)->>'status',
  'cancelled','order_get returns detail');
select cmp_ok((select count(*) from public.change_history
  where entity_type in('customer','shipping_destination','order')
    and changed_by='81000000-0000-0000-0000-000000000003'),'>=',8::bigint,
  'mutations append audit history');

select is((select count(*) from public.change_history
  where correlation_id='83000000-0000-4000-8000-000000000014'),6::bigint,
  'cancellation audits order, plan, allocation, reservation, container and shipping task');
select is((select before_data->>'allocated_weight_kg' from public.change_history
  where entity_type='ripening_lot' and correlation_id='83000000-0000-4000-8000-000000000014'),
  '2','plan cancellation audit captures the old allocation total');
select is((select after_data->>'allocated_weight_kg' from public.change_history
  where entity_type='ripening_lot' and correlation_id='83000000-0000-4000-8000-000000000014'),
  '0','plan cancellation audit captures trigger-maintained final totals');
select is((select operation from public.change_history
  where entity_type='ripening_allocation' and correlation_id='83000000-0000-4000-8000-000000000014'),
  'delete','allocation deletion has an explicit audit operation');
select is((select after_data->>'deleted' from public.change_history
  where entity_type='ripening_allocation' and correlation_id='83000000-0000-4000-8000-000000000014'),
  'true','allocation deletion has a tombstone');
select is((select before_data->>'order_id' from public.change_history
  where entity_type='ripening_allocation' and correlation_id='83000000-0000-4000-8000-000000000014'),
  current_setting('test.order')::jsonb->'data'->>'id','deleted allocation retains its order link');
select is((select before_data->>'status' from public.change_history
  where entity_type='inventory_reservation' and correlation_id='83000000-0000-4000-8000-000000000014'),
  'active','reservation audit captures its old state');
select is((select after_data->>'status' from public.change_history
  where entity_type='inventory_reservation' and correlation_id='83000000-0000-4000-8000-000000000014'),
  'released','reservation audit captures its released state');
select is((select count(*) from public.change_history
  where correlation_id='83000000-0000-4000-8000-000000000014'
    and changed_by='81000000-0000-0000-0000-000000000003' and reason='顧客都合'),
  6::bigint,'all related audits share the actor, reason and correlation');
select is((public.order_cancel(public.test_s2_req(
  '82000000-0000-4000-8000-000000000014','83000000-0000-4000-8000-000000000014',
  jsonb_build_object('order_id',current_setting('test.order')::jsonb->'data'->>'id',
    'expected_version',4,'reason','顧客都合'))))->>'idempotent_replay','true','cancellation replays after success');
select is((select count(*) from public.change_history
  where correlation_id='83000000-0000-4000-8000-000000000014'),6::bigint,
  'cancellation replay does not duplicate any audit');

-- A new draft order exercises explicit destination changes and replay.
select set_config('test.snapshot_order',public.order_register(public.test_s2_req(
  '82000000-0000-4000-8000-000000000020','83000000-0000-4000-8000-000000000020',
  jsonb_build_object('customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'shipping_destination_id',current_setting('test.destination1')::jsonb->'data'->>'id',
    'ordered_date','2027-06-10','scheduled_ship_date','2027-06-20',
    'variety_id',current_setting('test.order')::jsonb->'data'->>'variety_id',
    'grade_id',current_setting('test.order')::jsonb->'data'->>'grade_id',
    'ordered_weight_kg',2)))::text,true);
-- A migrated legacy draft preserves the original destination-edit contract.
reset role;
update public.orders set inventory_first=false where id=(current_setting('test.snapshot_order')::jsonb->'data'->>'id')::uuid;
set local role authenticated;
select set_config('test.destination_change_req',public.test_s2_req(
  '82000000-0000-4000-8000-000000000021','83000000-0000-4000-8000-000000000021',
  jsonb_build_object('order_id',current_setting('test.snapshot_order')::jsonb->'data'->>'id',
    'expected_version',1,'customer_id',current_setting('test.customer')::jsonb->'data'->>'id',
    'shipping_destination_id',current_setting('test.destination2')::jsonb->'data'->>'id',
    'ordered_date','2027-06-10','scheduled_ship_date','2027-06-20',
    'variety_id',current_setting('test.order')::jsonb->'data'->>'variety_id',
    'grade_id',current_setting('test.order')::jsonb->'data'->>'grade_id',
    'ordered_weight_kg',2,'reason','配送先変更'))::text,true);
select set_config('test.destination_changed',public.order_update(
  current_setting('test.destination_change_req')::jsonb)::text,true);
select is(current_setting('test.destination_changed')::jsonb->'data'->'shipping_destination_snapshot'->>'address',
  '支店住所','an explicit destination ID change refreshes the snapshot');
select is(public.order_update(current_setting('test.destination_change_req')::jsonb)->>'idempotent_replay',
  'true','destination change is idempotent');
select is((select count(*) from public.change_history
  where correlation_id='83000000-0000-4000-8000-000000000021'),1::bigint,
  'destination change replay does not duplicate history');

-- Exercise partial release and then full release on the draft reservation.
reset role;
delete from public.inventory_reservations where id='89400000-0000-0000-0000-000000000001';
insert into public.inventory_reservations(id,ripening_lot_id,container_id,reserved_weight_kg,
  created_by,updated_by)
values('89400000-0000-0000-0000-000000000002','89000000-0000-0000-0000-000000000001',
  '89300000-0000-0000-0000-000000000001',2,
  '81000000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000003');
select private.release_order_reservations('89000000-0000-0000-0000-000000000001',0.5,
  '81000000-0000-0000-0000-000000000003','部分解除','83000000-0000-4000-8000-000000000022');
select is((select before_data->>'reserved_weight_kg' from public.change_history
  where entity_type='inventory_reservation' and correlation_id='83000000-0000-4000-8000-000000000022'),
  '2','partial release audit retains original weight');
select is((select (after_data->>'reserved_weight_kg')::numeric from public.change_history
  where entity_type='inventory_reservation' and correlation_id='83000000-0000-4000-8000-000000000022'),
  1.5::numeric,'partial release audit retains remaining weight');
select is((select operation from public.change_history
  where entity_type='inventory_reservation' and correlation_id='83000000-0000-4000-8000-000000000022'),
  'update','partial release is a weight update');
select is((select after_data->>'status' from public.change_history
  where entity_type='inventory_reservation' and correlation_id='83000000-0000-4000-8000-000000000022'),
  'active','partial release keeps the reservation active');
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.customer_list(null,false)),0::bigint,
  'pending user cannot read customer list');
select is(public.order_get((current_setting('test.order')::jsonb->'data'->>'id')::uuid),null::jsonb,
  'pending user cannot read order detail');
reset role;

set local role anon;
select throws_ok($$select * from public.customer_list(null,false)$$,'42501',null,
  'anonymous cannot execute customer reference RPC');
reset role;

-- Literal searches must escape the escape character before percent/underscore.
update public.customers set name='A'||chr(92)||'B%_',address='TAIL'||chr(92)
where id=(current_setting('test.customer')::jsonb->'data'->>'id')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000003',true);
select is(
  (select count(*) from public.customer_list(sample.term,false)
   where customer_id=(current_setting('test.customer')::jsonb->'data'->>'id')::uuid),
  sample.expected,'customer literal search: '||sample.term)
from (values
  (chr(92),1::bigint),
  ('A'||chr(92)||'B%_',1::bigint),
  ('%_',1::bigint),
  ('A'||chr(92)||'B__',0::bigint),
  ('TAIL'||chr(92),1::bigint)
) as sample(term,expected);
select is(
  (select count(*) from public.order_list(null,sample.term)
   where order_id=(current_setting('test.order')::jsonb->'data'->>'id')::uuid),
  sample.expected,'order literal search: '||sample.term)
from (values
  (chr(92),1::bigint),
  ('A'||chr(92)||'B%_',1::bigint),
  ('%_',1::bigint),
  ('A'||chr(92)||'B__',0::bigint)
) as sample(term,expected);
reset role;

select * from finish();
rollback;
