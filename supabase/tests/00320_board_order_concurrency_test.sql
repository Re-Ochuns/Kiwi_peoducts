create extension if not exists dblink with schema extensions;
insert into auth.users(id,email,raw_user_meta_data) values
 ('58000000-0000-0000-0000-000000000001','plan-member@example.com','{}'),
 ('58000000-0000-0000-0000-000000000002','plan-pending@example.com','{}'),
 ('58000000-0000-0000-0000-000000000003','plan-admin@example.com','{}');
select private.set_user_access('58000000-0000-0000-0000-000000000001','active',array['member']);
select private.set_user_access('58000000-0000-0000-0000-000000000003','active',array['administrator']);
insert into public.ripening_rules(harvest_year,harvest_month,variety_id,ethylene_temperature,
 ethylene_hours,rest_temperature,rest_days,shippable_days,best_before_days)
values(2000,5,'a1000000-0000-0000-0000-000000000001',20,168,15,3,5,7)
on conflict do nothing;
update public.ripening_rules set ethylene_hours=168,rest_days=3,shippable_days=5,best_before_days=7
where variety_id='a1000000-0000-0000-0000-000000000001' and harvest_month=5 and is_active;
insert into public.customers(id,customer_code,name,postal_code,address)
values('58100000-0000-0000-0000-000000000001','BOARD118RACE','Dummy','000','Dummy');
insert into public.shipping_destinations(id,customer_id,destination_name,recipient_name,postal_code,address)
values('58200000-0000-0000-0000-000000000001','58100000-0000-0000-0000-000000000001','Dummy','Dummy','000','Dummy');
insert into public.orders(id,order_number,customer_id,shipping_destination_id,ordered_on,scheduled_ship_on,
 variety_id,grade_id,ordered_weight_kg,shipping_destination_snapshot,status)
select ('58300000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'BOARD118RACE-'||n,
 '58100000-0000-0000-0000-000000000001','58200000-0000-0000-0000-000000000001','2027-05-01','2027-06-01',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,'{}','confirmed'
from generate_series(1,2) n;
insert into public.sorting_results(id,display_id,receiving_lot_id,sorted_on,sorted_by,input_weight_kg,output_weight_kg,loss_weight_kg)
values('58400000-0000-0000-0000-000000000001','BOARD118RACE-S','aa000000-0000-0000-0000-000000000001',
 '2027-05-03','a7000000-0000-0000-0000-000000000001',48.25,10,38.25);
insert into public.containers(id,display_id,sorting_result_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,location_id)
values('58500000-0000-0000-0000-000000000001','BOARD118RACE-C','58400000-0000-0000-0000-000000000001',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,10,'cold_storage',
 'a8000000-0000-0000-0000-000000000001');

create function private.test118_criteria() returns jsonb language sql as $$
 select jsonb_build_object('scheduled_ship_date','2027-06-01',
  'variety_id','a1000000-0000-0000-0000-000000000001',
  'grade_id','a2000000-0000-0000-0000-000000000005','ordered_weight_kg',6);
$$;
create function private.test118_board_input(candidate jsonb) returns jsonb language sql as $$
 select private.test118_criteria()||jsonb_build_object(
  'candidate_kind',candidate->'kind','candidate_id',candidate->'id','candidate_version',candidate->'version',
  'customer_id','58100000-0000-0000-0000-000000000001',
  'shipping_destination_id','58200000-0000-0000-0000-000000000001',
  'storage_location_id','a8000000-0000-0000-0000-000000000001',
  'assigned_worker_id','a7000000-0000-0000-0000-000000000001');
$$;
create function private.test118_wait()
returns void language plpgsql as $$
declare n integer:=0;
begin
  loop
    exit when exists(select 1 from pg_stat_activity
      where application_name='board118_concurrency' and wait_event_type='Lock');
    n:=n+1;
    if n>100 then raise exception 'concurrent RPC did not reach a lock'; end if;
    perform pg_sleep(0.05);
  end loop;
end;
$$;

create function private.test118_call(input_value jsonb,key_value uuid) returns jsonb language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub','58000000-0000-0000-0000-000000000003',true);
 return public.board_order_confirm(jsonb_build_object('meta',jsonb_build_object('idempotency_key',key_value,'correlation_id',gen_random_uuid()),'input',input_value));
end;
$$;
select set_config('request.jwt.claim.sub','58000000-0000-0000-0000-000000000003',false);
create table private.test118_request as select private.test118_board_input(value) as input from jsonb_array_elements(public.board_order_candidates(private.test118_criteria())) where value->>'id'='58500000-0000-0000-0000-000000000001';
select extensions.dblink_connect('board118','host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres application_name=board118_concurrency');
create temporary table test118_results(label text,result jsonb);
begin;
insert into test118_results select 'winner',private.test118_call(input,'58600000-0000-4000-8000-000000000001') from private.test118_request;
select extensions.dblink_send_query('board118',$remote$select private.test118_call(input,'58600000-0000-4000-8000-000000000002') from private.test118_request$remote$);
select private.test118_wait();
commit;
insert into test118_results select 'loser',result from extensions.dblink_get_result('board118') as t(result jsonb);
select * from extensions.dblink_get_result('board118') as t(result jsonb);
select no_plan();
select is((select result->>'ok' from test118_results where label='winner'),'true','first order and plan succeeds');
select is((select result->'error'->>'code' from test118_results where label='loser'),'INVENTORY_UNAVAILABLE','waiting request rechecks committed stock');
select is((select reserved_weight_kg::numeric from public.containers where id='58500000-0000-0000-0000-000000000001'),6::numeric,'no double reservation');
select is((select count(*) from public.ripening_lots where created_by='58000000-0000-0000-0000-000000000003'),1::bigint,'loser leaves no plan');
select is((select count(*) from public.orders where customer_id='58100000-0000-0000-0000-000000000001'),3::bigint,'only one order added to two fixtures');
select is((select private.test118_call(input,'58600000-0000-4000-8000-000000000001')->>'idempotent_replay' from private.test118_request),'true','winner safely replays');
select * from finish();
select extensions.dblink_disconnect('board118');
-- Fixture cleanup restores the draft state before deleting allocations.
update public.ripening_lots set status='draft' where created_by='58000000-0000-0000-0000-000000000003';
delete from public.work_tasks where ripening_lot_id in (select id from public.ripening_lots where created_by='58000000-0000-0000-0000-000000000003');
delete from public.inventory_reservations where container_id='58500000-0000-0000-0000-000000000001';
delete from public.ripening_allocations where ripening_lot_id in
 (select id from public.ripening_lots where created_by='58000000-0000-0000-0000-000000000003');
delete from public.ripening_lots where created_by='58000000-0000-0000-0000-000000000003';
delete from public.containers where id='58500000-0000-0000-0000-000000000001';
delete from public.sorting_results where id='58400000-0000-0000-0000-000000000001';
delete from public.work_tasks where order_id in (select id from public.orders where customer_id='58100000-0000-0000-0000-000000000001');
delete from public.orders where customer_id='58100000-0000-0000-0000-000000000001';
delete from public.shipping_destinations where customer_id='58100000-0000-0000-0000-000000000001';
delete from public.customers where id='58100000-0000-0000-0000-000000000001';
-- Fixture-only cleanup: re-enable the append-only guard in the same transaction.
begin;
alter table public.change_history disable trigger change_history_append_only;
delete from public.change_history where changed_by in
 ('58000000-0000-0000-0000-000000000001','58000000-0000-0000-0000-000000000003');
alter table public.change_history enable trigger change_history_append_only;
commit;
delete from private.idempotency_records where executed_by in
 ('58000000-0000-0000-0000-000000000001','58000000-0000-0000-0000-000000000003');
delete from auth.users where id in ('58000000-0000-0000-0000-000000000001',
 '58000000-0000-0000-0000-000000000002','58000000-0000-0000-0000-000000000003');
drop table private.test118_request;
drop function private.test118_call(jsonb,uuid);
drop function private.test118_wait();
drop function private.test118_board_input(jsonb);
drop function private.test118_criteria();
