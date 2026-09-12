create extension if not exists dblink with schema extensions;
insert into auth.users(id,email,raw_user_meta_data) values
 ('58000000-0000-0000-0000-000000000001','task-concurrent-member@example.com','{}'),
 ('58000000-0000-0000-0000-000000000002','task-concurrent-pending@example.com','{}'),
 ('58000000-0000-0000-0000-000000000003','task-concurrent-admin@example.com','{}');
select private.set_user_access('58000000-0000-0000-0000-000000000001','active',array['member']);
select private.set_user_access('58000000-0000-0000-0000-000000000003','active',array['administrator']);
insert into public.customers(id,customer_code,name,postal_code,address)
values('58100000-0000-0000-0000-000000000001','TASK57','Dummy','000','Dummy');
insert into public.shipping_destinations(id,customer_id,destination_name,recipient_name,postal_code,address)
values('58200000-0000-0000-0000-000000000001','58100000-0000-0000-0000-000000000001','Dummy','Dummy','000','Dummy');
insert into public.orders(id,order_number,customer_id,shipping_destination_id,ordered_on,scheduled_ship_on,
 variety_id,grade_id,ordered_weight_kg,shipping_destination_snapshot,status)
select ('58300000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'TASK57-'||n,
 '58100000-0000-0000-0000-000000000001','58200000-0000-0000-0000-000000000001','2027-05-01','2027-06-01',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,'{}','confirmed'
from generate_series(1,2) n;
insert into public.sorting_results(id,display_id,receiving_lot_id,sorted_on,sorted_by,input_weight_kg,output_weight_kg,loss_weight_kg)
values('58400000-0000-0000-0000-000000000001','TASK57-S','aa000000-0000-0000-0000-000000000001',
 '2027-05-03','a7000000-0000-0000-0000-000000000001',48.25,10,38.25);
insert into public.containers(id,display_id,sorting_result_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,location_id)
values('58500000-0000-0000-0000-000000000001','TASK57-C','58400000-0000-0000-0000-000000000001',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,10,'cold_storage',
 'a8000000-0000-0000-0000-000000000001');

create function pg_temp.req(input_value jsonb,key_value uuid default gen_random_uuid())
returns jsonb language sql as $$
select jsonb_build_object('meta',jsonb_build_object('idempotency_key',key_value,'correlation_id',gen_random_uuid()),'input',input_value);
$$;
create function pg_temp.plan_input(weight_value numeric default 6)
returns jsonb language sql as $$
select jsonb_build_object(
 'variety_id','a1000000-0000-0000-0000-000000000001','grade_id','a2000000-0000-0000-0000-000000000005',
 'total_weight_kg',weight_value,'storage_location_id','a8000000-0000-0000-0000-000000000001',
 'assigned_worker_id','a7000000-0000-0000-0000-000000000001','planned_ethylene_at','2027-05-10T09:00:00+09:00',
 'planned_completion_at','2027-05-20T09:00:00+09:00',
 'allocations',jsonb_build_array(jsonb_build_object('allocation_type','reserve','allocated_weight_kg',weight_value)),
 'reservations',jsonb_build_array(jsonb_build_object('container_id','58500000-0000-0000-0000-000000000001','reserved_weight_kg',weight_value)));
$$;
create function pg_temp.transition_input() returns jsonb language sql as $$
select jsonb_build_object('ripening_lot_id',current_setting('test.plan')::jsonb->'data'->>'id',
 'expected_version',(current_setting('test.plan')::jsonb->'data'->>'version')::bigint,'reason','test');
$$;

select set_config('request.jwt.claim.sub','58000000-0000-0000-0000-000000000001',false);
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(pg_temp.plan_input()))::text,false);
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,false);
select extensions.dblink_connect('task57',
 'host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres application_name=task57_concurrency');
create temporary table task57_claims(worker text,jobs jsonb);
select no_plan();
begin;
-- Hold one outbox row while the second session claims other available rows.
select task_id from private.calendar_sync_jobs order by task_id limit 1 for update;
insert into task57_claims
select 'remote',jobs from extensions.dblink('task57','select public.calendar_sync_claim(5)') as t(jobs jsonb);
select is((select jsonb_array_length(jobs) from task57_claims where worker='remote'),2,'concurrent worker skips locked job and claims other two');
commit;
insert into task57_claims values('local',public.calendar_sync_claim(5));
select is((select jsonb_array_length(jobs) from task57_claims where worker='local'),1,'released job is claimed by next worker');
select is((select count(distinct j->'task'->>'id') from task57_claims c cross join lateral jsonb_array_elements(c.jobs) j),3::bigint,'workers never share a claimed task');
select is(jsonb_array_length(public.calendar_sync_claim(5)),0,'all leases prevent duplicate delivery');
select * from finish();
select extensions.dblink_disconnect('task57');

delete from public.work_tasks where ripening_lot_id=(current_setting('test.plan')::jsonb->'data'->>'id')::uuid;
update public.ripening_lots set status='draft' where id=(current_setting('test.plan')::jsonb->'data'->>'id')::uuid;
delete from public.inventory_reservations where container_id='58500000-0000-0000-0000-000000000001';
delete from public.ripening_allocations where ripening_lot_id=(current_setting('test.plan')::jsonb->'data'->>'id')::uuid;
delete from public.ripening_lots where id=(current_setting('test.plan')::jsonb->'data'->>'id')::uuid;
delete from public.containers where id='58500000-0000-0000-0000-000000000001';
delete from public.sorting_results where id='58400000-0000-0000-0000-000000000001';
delete from public.orders where customer_id='58100000-0000-0000-0000-000000000001';
delete from public.shipping_destinations where customer_id='58100000-0000-0000-0000-000000000001';
delete from public.customers where id='58100000-0000-0000-0000-000000000001';
begin;
alter table public.change_history disable trigger change_history_append_only;
delete from public.change_history where changed_by='58000000-0000-0000-0000-000000000001';
alter table public.change_history enable trigger change_history_append_only;
commit;
delete from private.idempotency_records where executed_by='58000000-0000-0000-0000-000000000001';
delete from auth.users where id in ('58000000-0000-0000-0000-000000000001','58000000-0000-0000-0000-000000000002','58000000-0000-0000-0000-000000000003');
