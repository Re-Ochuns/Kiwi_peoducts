begin;
select no_plan();

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

create function pg_temp.req(input_value jsonb,key_value uuid default gen_random_uuid())
returns jsonb language sql as $$
select jsonb_build_object('meta',jsonb_build_object('idempotency_key',key_value,'correlation_id',gen_random_uuid()),'input',input_value);
$$;
create function pg_temp.plan_input(weight_value numeric default 6)
returns jsonb language sql as $$
select jsonb_build_object(
 'variety_id','a1000000-0000-0000-0000-000000000001','grade_id','a2000000-0000-0000-0000-000000000005',
 'harvest_year',2027,'harvest_month',5,
 'total_weight_kg',weight_value,'storage_location_id','a8000000-0000-0000-0000-000000000001',
 'assigned_worker_id','a7000000-0000-0000-0000-000000000001','planned_ethylene_at','2027-05-10T09:00:00+09:00',
 'planned_completion_at','2027-05-20T09:00:00+09:00',
 'allocations',jsonb_build_array(jsonb_build_object('allocation_type','reserve','allocated_weight_kg',weight_value)),
 'reservations',jsonb_build_array(jsonb_build_object('container_id','53500000-0000-0000-0000-000000000001','reserved_weight_kg',weight_value)));
$$;
create function pg_temp.transition_input() returns jsonb language sql as $$
select jsonb_build_object('ripening_lot_id',current_setting('test.plan')::jsonb->'data'->>'id',
 'expected_version',(current_setting('test.plan')::jsonb->'data'->>'version')::bigint,'reason','test');
$$;

create function pg_temp.order_input(weight_value numeric) returns jsonb language sql as $$
select jsonb_build_object('customer_id','53100000-0000-0000-0000-000000000001',
 'shipping_destination_id','53200000-0000-0000-0000-000000000001',
 'ordered_date','2027-05-01','scheduled_ship_date','2027-05-20',
 'variety_id','a1000000-0000-0000-0000-000000000001','grade_id','a2000000-0000-0000-0000-000000000005',
 'ordered_weight_kg',weight_value,'reservations',jsonb_build_array(jsonb_build_object(
 'container_id','53500000-0000-0000-0000-000000000001','reserved_weight_kg',weight_value)));
$$;
create function pg_temp.reserved() returns numeric language sql as $$
select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'; $$;
create function pg_temp.oid(setting_name text) returns uuid language sql as $$ select (current_setting(setting_name)::jsonb->'data'->>'id')::uuid; $$;
create function pg_temp.order_allocation(setting_name text, weight_value numeric) returns jsonb language sql as $$
select jsonb_build_object('allocation_type','order','order_id',pg_temp.oid(setting_name),'allocated_weight_kg',weight_value); $$;
create function pg_temp.order_transition(setting_name text) returns jsonb language sql as $$
select jsonb_build_object('order_id',id,'expected_version',version,'reason','test') from public.orders where id=pg_temp.oid(setting_name); $$;

insert into public.ripening_rules(harvest_year,harvest_month,variety_id,ethylene_temperature,ethylene_hours,rest_temperature,rest_days,shippable_days,best_before_days)
values(2027,5,'a1000000-0000-0000-0000-000000000001',20,168,15,7,7,14);

set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.order_inventory_available()),0::bigint,'pending user cannot read inventory');
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select is(public.order_register(pg_temp.req(pg_temp.order_input(4)))->'error'->>'code','AUTH_FORBIDDEN','member cannot register order');
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000003',true);
select is(pg_temp.reserved(),0::numeric,'viewing inventory does not reserve');
select set_config('test.first',public.order_register(pg_temp.req(pg_temp.order_input(4),'10900000-0000-4000-8000-000000000001'))::text,true);
select is(current_setting('test.first')::jsonb->'data'->>'status','confirmed','order and reservation confirm together');
select is(pg_temp.reserved(),4::numeric,'order reserves four kg before plan');
select is(public.order_register(pg_temp.req(pg_temp.order_input(4),'10900000-0000-4000-8000-000000000001'))->>'idempotent_replay','true','retry replays result');
select is(pg_temp.reserved(),4::numeric,'retry does not double reserve');
select is(public.order_register(pg_temp.req(pg_temp.order_input(7)))->'error'->>'code','INVENTORY_UNAVAILABLE','insufficient inventory rejected');
select is((select count(*) from public.orders where inventory_first),1::bigint,'failed reservation rolls back order');
select is(public.order_register(pg_temp.req(pg_temp.order_input(2)||'{"ordered_weight_kg":3}'))->'error'->>'code','ORDER_RESERVATION_MISMATCH','weight mismatch rejected');
select is(jsonb_array_length(public.order_get(pg_temp.oid('test.first'))->'reservations'),1,'order detail shows owned stock');
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(pg_temp.plan_input(3)||jsonb_build_object('allocations',jsonb_build_array(
 pg_temp.order_allocation('test.first',2),jsonb_build_object('allocation_type','reserve','allocated_weight_kg',1)))))::text,true);
select is(current_setting('test.plan')::jsonb->>'ok','true','mixed plan uses owned reservation and reserve');
select is(pg_temp.reserved(),5::numeric,'transfer adds only reserve weight');
select is(public.ripening_plan_cancel(pg_temp.req(pg_temp.transition_input()))->>'ok','true','plan cancellation succeeds');
select is(pg_temp.reserved(),4::numeric,'plan cancellation restores order holds and frees reserve');
select is(public.order_update(pg_temp.req(pg_temp.order_input(5)||pg_temp.order_transition('test.first')))->'data'->>'status','confirmed','editing order adjusts holds and confirms atomically');
select is(pg_temp.reserved(),5::numeric,'order increased to five');
select is(public.order_update(pg_temp.req(pg_temp.order_input(11)||pg_temp.order_transition('test.first')))->'error'->>'code','INVENTORY_UNAVAILABLE','failed increase rejected');
select is(pg_temp.reserved(),5::numeric,'failed edit restores previous holds');
select set_config('test.second',public.order_register(pg_temp.req(pg_temp.order_input(2)))::text,true);
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(pg_temp.plan_input(6)||jsonb_build_object('allocations',jsonb_build_array(
 pg_temp.order_allocation('test.first',3),pg_temp.order_allocation('test.second',2),jsonb_build_object('allocation_type','reserve','allocated_weight_kg',1)))))::text,true);
select is(current_setting('test.plan')::jsonb->>'ok','true','two owners and reserve can share one source');
select is(pg_temp.reserved(),8::numeric,'shared plan retains unplanned owner weight');
select is(public.order_cancel(pg_temp.req(pg_temp.order_transition('test.first')))->>'ok','true','cancel one order');
select is(pg_temp.reserved(),3::numeric,'only cancelled owner released');
select set_config('test.plan',(jsonb_build_object('data',public.ripening_plan_get(pg_temp.oid('test.plan'))))::text,true);
select is(public.ripening_plan_cancel(pg_temp.req(pg_temp.transition_input()))->>'ok','true','cancel shared plan after order removal');
select is(pg_temp.reserved(),2::numeric,'other owner retains two kg');
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(pg_temp.plan_input(3)||jsonb_build_object('allocations',jsonb_build_array(
 pg_temp.order_allocation('test.second',2),jsonb_build_object('allocation_type','reserve','allocated_weight_kg',1)))))::text,true);
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
select is(current_setting('test.plan')::jsonb->'data'->>'status','confirmed','owned mixed plan confirms');
select is((select count(*) from public.work_tasks where ripening_lot_id=pg_temp.oid('test.plan')),3::bigint,'plan tasks still generated');
select is((select current_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),10::numeric,'reservations never reduce physical stock');
select ok(exists(select 1 from public.change_history where entity_type='inventory_reservation' and correlation_id is not null),'reservation audit records correlation');
select set_config('test.injection',public.ripening_ethylene_injection_complete(pg_temp.req(jsonb_build_object(
 'ripening_lot_id',pg_temp.oid('test.plan'),'expected_version',(current_setting('test.plan')::jsonb->'data'->>'version')::bigint,
 'location_id','a8000000-0000-0000-0000-000000000001','performed_by','a7000000-0000-0000-0000-000000000001',
 'actual_temperature',20,'checked',true)))::text,true);
select diag(current_setting('test.injection')::jsonb->'error');
select is(current_setting('test.injection')::jsonb->>'ok','true','shared owned and reserve source injects successfully');
select is(pg_temp.reserved(),0::numeric,'injection consumes all planned reservations');
select is((select current_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),7::numeric,'one source deducted once for combined three kg');
select is((select count(*) from public.inventory_events where ripening_lot_id=pg_temp.oid('test.plan') and event_type='ripening_out'),1::bigint,'one event per source even when ownership is split');
select is((select count(*) from public.label_jobs j join public.containers c on c.id=j.container_id where c.ripening_lot_id=pg_temp.oid('test.plan')),1::bigint,'ripening label creation preserved');
select is(public.order_cancel(pg_temp.req(pg_temp.order_transition('test.second')))->'error'->>'code','CONFLICT_STALE','started order cannot be cancelled');
select * from finish();
rollback;
