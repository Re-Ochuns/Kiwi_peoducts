-- Real sessions: the loser must wait before checking the committed balance.
create extension if not exists dblink with schema extensions;
insert into auth.users(id,email,raw_user_meta_data) values
 ('53000000-0000-0000-0000-000000000001','plan-member@example.com','{}'),
 ('53000000-0000-0000-0000-000000000002','plan-pending@example.com','{}'),
 ('53000000-0000-0000-0000-000000000003','plan-admin@example.com','{}');
select private.set_user_access('53000000-0000-0000-0000-000000000001','active',array['member']);
select private.set_user_access('53000000-0000-0000-0000-000000000003','active',array['administrator']);
insert into public.customers(id,customer_code,name,postal_code,address)
values('53100000-0000-0000-0000-000000000001','PLAN53','Dummy','000','Dummy');
insert into public.shipping_destinations(id,customer_id,destination_name,recipient_name,postal_code,address)
values('53200000-0000-0000-0000-000000000001','53100000-0000-0000-0000-000000000001','Dummy','Dummy','000','Dummy');
insert into public.orders(id,order_number,customer_id,shipping_destination_id,ordered_on,scheduled_ship_on,
 variety_id,grade_id,ordered_weight_kg,shipping_destination_snapshot,status)
select ('53300000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'PLAN53-'||n,
 '53100000-0000-0000-0000-000000000001','53200000-0000-0000-0000-000000000001','2027-05-01','2027-06-01',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,'{}','confirmed'
from generate_series(1,2) n;
insert into public.sorting_results(id,display_id,receiving_lot_id,sorted_on,sorted_by,input_weight_kg,output_weight_kg,loss_weight_kg)
values('53400000-0000-0000-0000-000000000001','PLAN53-S','aa000000-0000-0000-0000-000000000001',
 '2027-05-03','a7000000-0000-0000-0000-000000000001',48.25,10,38.25);
insert into public.containers(id,display_id,sorting_result_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,location_id)
values('53500000-0000-0000-0000-000000000001','PLAN53-C','53400000-0000-0000-0000-000000000001',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,10,'cold_storage',
 'a8000000-0000-0000-0000-000000000001');

create function private.test53_plan_input(weight_value numeric default 6)
returns jsonb language sql as $$
select jsonb_build_object(
 'variety_id','a1000000-0000-0000-0000-000000000001','grade_id','a2000000-0000-0000-0000-000000000005',
 'total_weight_kg',weight_value,'storage_location_id','a8000000-0000-0000-0000-000000000001',
 'assigned_worker_id','a7000000-0000-0000-0000-000000000001','planned_ethylene_at','2027-05-10T09:00:00+09:00',
 'planned_completion_at','2027-05-20T09:00:00+09:00',
 'allocations',jsonb_build_array(jsonb_build_object('allocation_type','reserve','allocated_weight_kg',weight_value)),
 'reservations',jsonb_build_array(jsonb_build_object('container_id','53500000-0000-0000-0000-000000000001','reserved_weight_kg',weight_value)));
$$;

create function private.test53_call(input_value jsonb,key_value uuid)
returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
  return public.ripening_plan_register(jsonb_build_object('meta',jsonb_build_object(
    'correlation_id',gen_random_uuid(),'idempotency_key',key_value),'input',input_value));
end;
$$;
create function private.test53_wait()
returns void language plpgsql as $$
declare n integer:=0;
begin
  loop
    exit when exists(select 1 from pg_stat_activity
      where application_name='plan53_concurrency' and wait_event_type='Lock');
    n:=n+1;
    if n>100 then raise exception 'concurrent RPC did not reach a lock'; end if;
    perform pg_sleep(0.05);
  end loop;
end;
$$;
select extensions.dblink_connect('plan53',
  'host=127.0.0.1 port=5432 dbname=postgres user=postgres password=postgres application_name=plan53_concurrency');
create temporary table test53_results(label text,result jsonb);
begin;
insert into test53_results values('winner',
  private.test53_call(private.test53_plan_input(),'53600000-0000-4000-8000-000000000010'));
select extensions.dblink_send_query('plan53',$remote$
  select private.test53_call(private.test53_plan_input(),'53600000-0000-4000-8000-000000000011')
$remote$);
select private.test53_wait();
commit;
insert into test53_results select 'loser',result from extensions.dblink_get_result('plan53') as t(result jsonb);
select * from extensions.dblink_get_result('plan53') as t(result jsonb);
select no_plan();
select is((select result->>'ok' from test53_results where label='winner'),'true','first concurrent plan wins');
select is((select result->'error'->>'code' from test53_results where label='loser'),'INVENTORY_UNAVAILABLE','waiting plan rechecks available weight');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),6::numeric,'concurrent requests cannot double reserve');
select is((select count(*) from public.ripening_lots where created_by='53000000-0000-0000-0000-000000000001'),1::bigint,'losing transaction leaves no plan');

-- A request waiting on the planning lock can use the remaining balance.
begin;
select pg_advisory_xact_lock(53,0);
select extensions.dblink_send_query('plan53',$remote$
  select private.test53_call(private.test53_plan_input(4),'53600000-0000-4000-8000-000000000012')
$remote$);
select private.test53_wait();
-- Commit only after observing the remote session waiting on the lock.
commit;
insert into test53_results select 'second',result from extensions.dblink_get_result('plan53') as t(result jsonb);
select * from extensions.dblink_get_result('plan53') as t(result jsonb);
select is((select result->>'ok' from test53_results where label='second'),'true','remaining four kilograms can be reserved');
select is(private.test53_call(private.test53_plan_input(4),'53600000-0000-4000-8000-000000000012')->>'idempotent_replay','true','committed request replays without another reservation');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),10::numeric,'partial reservations exactly fill container');

-- Two sessions contend for the same fresh idempotency key (no inventory needed).
begin;
insert into test53_results values('empty-winner',private.test53_call(
 private.test53_plan_input()||'{"reservations":[],"allocations":[]}',
 '53600000-0000-4000-8000-000000000013'));
select extensions.dblink_send_query('plan53',$remote$
 select private.test53_call(private.test53_plan_input()||'{"reservations":[],"allocations":[]}',
 '53600000-0000-4000-8000-000000000013')
$remote$);
select private.test53_wait();
commit;
insert into test53_results select 'empty-replay',result from extensions.dblink_get_result('plan53') as t(result jsonb);
select * from extensions.dblink_get_result('plan53') as t(result jsonb);
select is((select result->>'idempotent_replay' from test53_results where label='empty-replay'),'true','simultaneous identical key replays after winner commits');
select is((select result->'data'->>'id' from test53_results where label='empty-winner'),
 (select result->'data'->>'id' from test53_results where label='empty-replay'),'concurrent replay returns same plan');

-- Existing order cancellation and new plan allocation share the same lock.
begin;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000003',true);
insert into test53_results values('order-cancel',public.order_cancel(jsonb_build_object(
 'meta',jsonb_build_object('correlation_id',gen_random_uuid(),'idempotency_key',gen_random_uuid()),
 'input',jsonb_build_object('order_id','53300000-0000-0000-0000-000000000001',
   'expected_version',1,'reason','concurrent cancellation'))));
select extensions.dblink_send_query('plan53',$remote$
 select private.test53_call(private.test53_plan_input()||'{"reservations":[],"allocations":[
 {"allocation_type":"order","order_id":"53300000-0000-0000-0000-000000000001","allocated_weight_kg":1}]}',
 '53600000-0000-4000-8000-000000000014')
$remote$);
select private.test53_wait();
commit;
insert into test53_results select 'order-loser',result from extensions.dblink_get_result('plan53') as t(result jsonb);
select * from extensions.dblink_get_result('plan53') as t(result jsonb);
select is((select result->>'ok' from test53_results where label='order-cancel'),'true','order cancellation succeeds during competing plan creation');
select is((select result->'error'->>'code' from test53_results where label='order-loser'),'ORDER_UNAVAILABLE','waiting plan sees committed order cancellation');
select is((select allocated_weight_kg::numeric from public.orders where id='53300000-0000-0000-0000-000000000001'),0::numeric,'cancelled order has no losing allocation');

select * from finish();

select extensions.dblink_disconnect('plan53');
delete from public.inventory_reservations where container_id='53500000-0000-0000-0000-000000000001';
delete from public.ripening_allocations where ripening_lot_id in
 (select id from public.ripening_lots where created_by='53000000-0000-0000-0000-000000000001');
delete from public.ripening_lots where created_by='53000000-0000-0000-0000-000000000001';
delete from public.containers where id='53500000-0000-0000-0000-000000000001';
delete from public.sorting_results where id='53400000-0000-0000-0000-000000000001';
delete from public.orders where customer_id='53100000-0000-0000-0000-000000000001';
delete from public.shipping_destinations where customer_id='53100000-0000-0000-0000-000000000001';
delete from public.customers where id='53100000-0000-0000-0000-000000000001';
-- Fixture-only cleanup: re-enable the append-only guard in the same transaction.
begin;
alter table public.change_history disable trigger change_history_append_only;
delete from public.change_history where changed_by in
 ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000003');
alter table public.change_history enable trigger change_history_append_only;
commit;
delete from private.idempotency_records where executed_by in
 ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000003');
delete from auth.users where id in ('53000000-0000-0000-0000-000000000001',
 '53000000-0000-0000-0000-000000000002','53000000-0000-0000-0000-000000000003');
drop function private.test53_wait();
drop function private.test53_call(jsonb,uuid);
drop function private.test53_plan_input(numeric);
