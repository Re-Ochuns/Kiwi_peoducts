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

create function private.test109_order_input(weight_value numeric) returns jsonb language sql as $$
select jsonb_build_object('customer_id','53100000-0000-0000-0000-000000000001',
 'shipping_destination_id','53200000-0000-0000-0000-000000000001',
 'ordered_date','2027-05-01','scheduled_ship_date','2027-05-20',
 'variety_id','a1000000-0000-0000-0000-000000000001','grade_id','a2000000-0000-0000-0000-000000000005',
 'ordered_weight_kg',weight_value,'reservations',jsonb_build_array(jsonb_build_object(
 'container_id','53500000-0000-0000-0000-000000000001','reserved_weight_kg',weight_value)));
$$;

create function private.test109_call(weight_value numeric,key_value uuid) returns jsonb language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000003',true);
 return public.order_register(jsonb_build_object('meta',jsonb_build_object('correlation_id',gen_random_uuid(),'idempotency_key',key_value),
 'input',private.test109_order_input(weight_value)));
end; $$;
create function private.test109_wait() returns void language plpgsql as $$
declare n integer:=0;
begin
 loop
  exit when exists(select 1 from pg_stat_activity where application_name='order109_concurrency' and wait_event_type='Lock');
  n:=n+1; if n>100 then raise exception 'concurrent order did not reach lock'; end if;
  perform pg_sleep(0.05);
 end loop;
end; $$;
select extensions.dblink_connect('order109','host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres application_name=order109_concurrency');
create temporary table order109_results(label text,result jsonb);
begin;
insert into order109_results values('winner',private.test109_call(6,'10900000-0000-4000-8000-000000000010'));
select extensions.dblink_send_query('order109',$remote$select private.test109_call(6,'10900000-0000-4000-8000-000000000011')$remote$);
select private.test109_wait();
commit;
insert into order109_results select 'loser',result from extensions.dblink_get_result('order109') as t(result jsonb);
select * from extensions.dblink_get_result('order109') as t(result jsonb);
select no_plan();
select is((select result->>'ok' from order109_results where label='winner'),'true','first order wins');
select is((select result->'error'->>'code' from order109_results where label='loser'),'INVENTORY_UNAVAILABLE','waiting order rechecks balance');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),6::numeric,'only winning order holds stock');
select is((select count(*) from public.orders where inventory_first),1::bigint,'loser leaves no order');
begin;
insert into order109_results values('same-winner',private.test109_call(4,'10900000-0000-4000-8000-000000000012'));
select extensions.dblink_send_query('order109',$remote$select private.test109_call(4,'10900000-0000-4000-8000-000000000012')$remote$);
select private.test109_wait();
commit;
insert into order109_results select 'same-replay',result from extensions.dblink_get_result('order109') as t(result jsonb);
select * from extensions.dblink_get_result('order109') as t(result jsonb);
select is((select result->>'idempotent_replay' from order109_results where label='same-replay'),'true','simultaneous duplicate is replayed');
select is((select result->'data'->>'id' from order109_results where label='same-winner'),(select result->'data'->>'id' from order109_results where label='same-replay'),'same order returned to both requests');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),10::numeric,'no duplicate holds');
select * from finish();
select extensions.dblink_disconnect('order109');
delete from public.inventory_reservations where container_id='53500000-0000-0000-0000-000000000001';
delete from public.work_tasks where order_id in (select id from public.orders where customer_id='53100000-0000-0000-0000-000000000001');
delete from public.orders where customer_id='53100000-0000-0000-0000-000000000001';
delete from public.containers where id='53500000-0000-0000-0000-000000000001';
delete from public.sorting_results where id='53400000-0000-0000-0000-000000000001';
delete from public.shipping_destinations where customer_id='53100000-0000-0000-0000-000000000001';
delete from public.customers where id='53100000-0000-0000-0000-000000000001';
begin;
alter table public.change_history disable trigger change_history_append_only;
delete from public.change_history where changed_by in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000003');
alter table public.change_history enable trigger change_history_append_only;
commit;
delete from private.idempotency_records where executed_by in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000003');
delete from auth.users where id in ('53000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000002','53000000-0000-0000-0000-000000000003');
drop function private.test109_wait();
drop function private.test109_call(numeric,uuid);
drop function private.test109_order_input(numeric);
