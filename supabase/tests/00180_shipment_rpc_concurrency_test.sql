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

update public.orders set ordered_weight_kg=case when order_number='PLAN53-1' then 6 else 4 end,
 shipping_destination_snapshot='{"address":"fixture"}',status='in_progress';
insert into public.ripening_lots(id,display_id,variety_id,grade_id,total_weight_kg,storage_location_id,
 planned_ethylene_at,planned_completion_at,assigned_worker_id,status)
values('64000000-0000-0000-0000-000000000001','SHIP64-LOT',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',12,
 'a8000000-0000-0000-0000-000000000001',now()-interval '10 days',now()-interval '1 day',
 'a7000000-0000-0000-0000-000000000001','draft');
insert into public.ripening_allocations(ripening_lot_id,allocation_type,order_id,allocated_weight_kg) values
 ('64000000-0000-0000-0000-000000000001','order','53300000-0000-0000-0000-000000000001',6),
 ('64000000-0000-0000-0000-000000000001','order','53300000-0000-0000-0000-000000000002',4),
 ('64000000-0000-0000-0000-000000000001','reserve',null,2);
insert into public.sorting_results(id,display_id,receiving_lot_id,sorted_on,sorted_by,input_weight_kg,output_weight_kg,loss_weight_kg)
values('53400000-0000-0000-0000-000000000001','PLAN53-S','aa000000-0000-0000-0000-000000000001',
 '2027-05-03','a7000000-0000-0000-0000-000000000001',48.25,12,36.25);
insert into public.containers(id,display_id,sorting_result_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,location_id)
values('53500000-0000-0000-0000-000000000001','PLAN53-C','53400000-0000-0000-0000-000000000001',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',12,12,'cold_storage',
 'a8000000-0000-0000-0000-000000000001');

insert into public.inventory_reservations(ripening_lot_id,container_id,reserved_weight_kg)
 values('64000000-0000-0000-0000-000000000001','53500000-0000-0000-0000-000000000001',12);
update public.ripening_lots set status='confirmed' where display_id='SHIP64-LOT';
update public.ripening_lots set status='in_progress' where display_id='SHIP64-LOT';
update public.inventory_reservations set status='consumed',consumed_at=now() where ripening_lot_id='64000000-0000-0000-0000-000000000001';
update public.ripening_lots set status='completed' where display_id='SHIP64-LOT';

insert into public.containers(id,display_id,ripening_lot_id,variety_id,grade_id,original_weight_kg,current_weight_kg,
 status,location_id,shippable_until,best_before_at) values
 ('64100000-0000-0000-0000-000000000001','SHIP64-C1','64000000-0000-0000-0000-000000000001',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',8,8,'shippable',
 'a8000000-0000-0000-0000-000000000001',now()+interval '5 days',now()+interval '7 days'),
 ('64100000-0000-0000-0000-000000000002','SHIP64-C2','64000000-0000-0000-0000-000000000001',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',4,4,'shippable',
 'a8000000-0000-0000-0000-000000000001',now()+interval '5 days',now()+interval '7 days');

create function private.test64_input(amount numeric default 2,ord uuid default '53300000-0000-0000-0000-000000000001',
 cont uuid default '64100000-0000-0000-0000-000000000001') returns jsonb language sql as $$
 select jsonb_build_object('order_id',ord,'expected_order_version',(select version from public.orders where id=ord),
 'worker_id','a7000000-0000-0000-0000-000000000001','checked',true,'reason','出荷テスト',
 'lines',jsonb_build_array(jsonb_build_object('container_id',cont,'expected_version',(select version from public.containers where id=cont),'shipped_weight_kg',amount)));
$$;

create function private.test64_call(fn text,v jsonb,k uuid) returns jsonb language plpgsql as $$
declare req jsonb;
begin
 perform set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
 req:=jsonb_build_object('meta',jsonb_build_object('idempotency_key',k,'correlation_id',gen_random_uuid()),'input',v);
 return case when fn='confirm' then public.shipment_confirm(req) else public.shipment_cancel(req) end;
end;
$$;
create function private.test64_wait() returns void language plpgsql as $$
declare n integer:=0;
begin
 loop
 exit when exists(select 1 from pg_stat_activity where application_name='ship64_concurrency' and wait_event_type='Lock');
 n:=n+1; if n>100 then raise exception 'concurrent RPC did not wait'; end if;
 perform pg_sleep(0.05);
 end loop;
end;
$$;
create table private.test64_inputs(label text primary key,v jsonb);
insert into private.test64_inputs values('first',private.test64_input());
create temporary table test64_results(label text,result jsonb);
select extensions.dblink_connect('ship64','host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres application_name=ship64_concurrency');
begin;
insert into test64_results values('first',private.test64_call('confirm',(select v from private.test64_inputs where label='first'),'64600000-0000-4000-8000-000000000001'));
select extensions.dblink_send_query('ship64',$remote$ select private.test64_call('confirm',(select v from private.test64_inputs where label='first'),'64600000-0000-4000-8000-000000000001') $remote$);
select private.test64_wait();
commit;
insert into test64_results select 'replay',result from extensions.dblink_get_result('ship64') as t(result jsonb);
select * from extensions.dblink_get_result('ship64') as t(result jsonb);
select no_plan();
select is((select result->>'ok' from test64_results where label='first'),'true','winner commits');
select is((select result->>'idempotent_replay' from test64_results where label='replay'),'true','simultaneous identical request replays');
select is((select count(*) from public.shipments),1::bigint,'only one shipment');
select is((select current_weight_kg::numeric from public.containers where display_id='SHIP64-C1'),6::numeric,'one decrement');
insert into private.test64_inputs values('second',private.test64_input(4)),
 ('compete',private.test64_input(4,'53300000-0000-0000-0000-000000000002'));
begin;
insert into test64_results values('second',private.test64_call('confirm',(select v from private.test64_inputs where label='second'),'64600000-0000-4000-8000-000000000002'));
select extensions.dblink_send_query('ship64',$remote$ select private.test64_call('confirm',(select v from private.test64_inputs where label='compete'),'64600000-0000-4000-8000-000000000003') $remote$);
select private.test64_wait();
commit;
insert into test64_results select 'loser',result from extensions.dblink_get_result('ship64') as t(result jsonb);
select * from extensions.dblink_get_result('ship64') as t(result jsonb);
select is((select result->'error'->>'code' from test64_results where label='loser'),'CONFLICT_STALE','competing order rechecks container version');
select is((select current_weight_kg::numeric from public.containers where display_id='SHIP64-C1'),2::numeric,'never overdraw stock');
select is(private.test64_call('confirm',private.test64_input(4,'53300000-0000-0000-0000-000000000002'),gen_random_uuid())->'error'->>'code','INVENTORY_UNAVAILABLE','fresh retry rejects insufficient stock');
insert into private.test64_inputs select 'cancel',jsonb_build_object('shipment_id',result->'data'->>'id','expected_version',1,'reason','concurrent cancellation') from test64_results where label='second';
begin;
insert into test64_results values('cancel',private.test64_call('cancel',(select v from private.test64_inputs where label='cancel'),'64600000-0000-4000-8000-000000000004'));
select extensions.dblink_send_query('ship64',$remote$ select private.test64_call('cancel',(select v from private.test64_inputs where label='cancel'),'64600000-0000-4000-8000-000000000004') $remote$);
select private.test64_wait();
commit;
insert into test64_results select 'cancel-replay',result from extensions.dblink_get_result('ship64') as t(result jsonb);
select * from extensions.dblink_get_result('ship64') as t(result jsonb);
select is((select result->>'idempotent_replay' from test64_results where label='cancel-replay'),'true','simultaneous cancellation replays');
select is((select count(*) from public.inventory_events where event_type='shipment_cancel'),1::bigint,'one reverse event');
select is((select current_weight_kg::numeric from public.containers where display_id='SHIP64-C1'),6::numeric,'one restoration');
-- Hold the planning lock while the worker's statement crosses the deadline.
insert into private.test64_inputs values('expiry',private.test64_input(1));
begin;
select pg_advisory_xact_lock(53,0);
select extensions.dblink_send_query('ship64',$remote$ select private.test64_call('confirm',(select v from private.test64_inputs where label='expiry'),'64600000-0000-4000-8000-000000000005') $remote$);
select private.test64_wait();
-- Pick the deadline after the remote statement began, then wait past it.
update public.containers set shippable_until=clock_timestamp()+interval '100 milliseconds',
 best_before_at=clock_timestamp()+interval '100 milliseconds' where display_id='SHIP64-C1';
select pg_sleep(0.2);
commit;
insert into test64_results select 'expiry',result from extensions.dblink_get_result('ship64') as t(result jsonb);
select * from extensions.dblink_get_result('ship64') as t(result jsonb);
select is((select result->'error'->>'code' from test64_results where label='expiry'),'CONTAINER_EXPIRED','deadline is rechecked after lock wait');
select is((select current_weight_kg::numeric from public.containers where display_id='SHIP64-C1'),6::numeric,'expired request leaves stock unchanged');
select is((select count(*) from public.shipments),2::bigint,'expired request creates no shipment');
select * from finish();
select extensions.dblink_disconnect('ship64');
-- Fixture cleanup is restricted to this test's IDs, in a single transaction.
begin;
set local session_replication_role=replica;
delete from private.calendar_sync_jobs where task_id in (select id from public.work_tasks where order_id in (select id from public.orders where order_number like 'PLAN53-%'));
delete from public.work_tasks where order_id in (select id from public.orders where order_number like 'PLAN53-%');
delete from public.inventory_events where created_by='53000000-0000-0000-0000-000000000001';
delete from public.shipment_lines where created_by='53000000-0000-0000-0000-000000000001';
delete from public.shipments where created_by='53000000-0000-0000-0000-000000000001';
delete from public.inventory_reservations where ripening_lot_id='64000000-0000-0000-0000-000000000001';
delete from public.ripening_allocations where ripening_lot_id='64000000-0000-0000-0000-000000000001';
delete from public.containers where ripening_lot_id='64000000-0000-0000-0000-000000000001' or id='53500000-0000-0000-0000-000000000001';
delete from public.ripening_lots where id='64000000-0000-0000-0000-000000000001';
delete from public.sorting_results where id='53400000-0000-0000-0000-000000000001';
delete from public.orders where customer_id='53100000-0000-0000-0000-000000000001';
delete from public.shipping_destinations where customer_id='53100000-0000-0000-0000-000000000001';
delete from public.customers where id='53100000-0000-0000-0000-000000000001';
delete from public.change_history where changed_by in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000003');
delete from private.idempotency_records where executed_by='53000000-0000-0000-0000-000000000001';
delete from public.user_roles where user_id in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000002','53000000-0000-0000-0000-000000000003');
delete from public.profiles where id in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000002','53000000-0000-0000-0000-000000000003');
delete from auth.users where id in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000002','53000000-0000-0000-0000-000000000003');
commit;
drop table private.test64_inputs;
drop function private.test64_wait();
drop function private.test64_call(text,jsonb,uuid);
drop function private.test64_input(numeric,uuid,uuid);
