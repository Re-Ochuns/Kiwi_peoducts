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
-- Unit tests exercise parsing and calculation boundaries separately from RPC integration.
select is(private.ripening_timestamp('{"at":"2027-05-10T09:00:00+09:00"}','at'),
 '2027-05-10 00:00:00+00'::timestamptz,'timestamp preserves timezone');
select throws_ok($$select private.ripening_timestamp('{"at":"2027-02-30T00:00:00Z"}','at')$$,
 'KW400','VALIDATION_FAILED','invalid date rejected');
select throws_ok($$select private.ripening_timestamp('{"at":"2027-05-10T09:00:00"}','at')$$,
 'KW400','VALIDATION_FAILED','timezone required');
select throws_ok($$select private.ripening_plan_input(pg_temp.plan_input(0.001))$$,
 'KW400','VALIDATION_FAILED','sub-0.01 kg precision rejected');
select throws_ok($$select private.ripening_plan_input(pg_temp.plan_input()||'{"allocations":null}')$$,
 'KW400','VALIDATION_FAILED','array null rejected');
select throws_ok($$select private.ripening_plan_input(pg_temp.plan_input()||'{"allocations":[1]}')$$,
 'KW400','VALIDATION_FAILED','non-object line rejected');
select throws_ok($$select private.ripening_plan_input(pg_temp.plan_input()||'{"allocations":[{"allocation_type":"reserve","allocated_weight_kg":1},{"allocation_type":"reserve","allocated_weight_kg":1}]}')$$,
 'KW400','VALIDATION_FAILED','duplicate reserve line rejected');
select throws_ok($$select private.ripening_plan_input(pg_temp.plan_input()||'{"total_weight_kg":5}')$$,
 'KW400','RIPENING_WEIGHT_MISMATCH','sum cannot exceed total');

set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000002',true);
select is(public.ripening_plan_register(pg_temp.req(pg_temp.plan_input()))->'error'->>'code','AUTH_FORBIDDEN','pending mutation denied');
select is((select count(*) from public.ripening_inventory_available()),0::bigint,'pending inventory hidden');
select set_config('request.jwt.claim.sub','',true);
select is(public.ripening_plan_register(pg_temp.req(pg_temp.plan_input()))->'error'->>'code','AUTH_REQUIRED','missing login denied');
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select throws_ok($$update public.containers set reserved_weight_kg=0$$,'42501',null,'direct writes denied');
select is(public.ripening_plan_register('{}')->'error'->>'code','VALIDATION_FAILED','invalid envelope rejected');
select is(public.ripening_plan_register(pg_temp.req(pg_temp.plan_input()||'{"use_type":"order"}'))->'error'->>'code','VALIDATION_FAILED','derived input rejected');

select set_config('test.input',(pg_temp.plan_input()||'{"allocations":[
 {"allocation_type":"order","order_id":"53300000-0000-0000-0000-000000000001","allocated_weight_kg":2},
 {"allocation_type":"order","order_id":"53300000-0000-0000-0000-000000000002","allocated_weight_kg":2},
 {"allocation_type":"reserve","allocated_weight_kg":2}]}')::text,true);
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(current_setting('test.input')::jsonb,
 '53600000-0000-4000-8000-000000000001'))::text,true);
select is(current_setting('test.plan')::jsonb->>'ok','true','member creates plan');
select is(current_setting('test.plan')::jsonb->'data'->>'use_type','mixed','multiple orders and reserve derive mixed');
select is(jsonb_array_length(current_setting('test.plan')::jsonb->'data'->'allocations'),3,'three allocation lines');
select is((select available_weight_kg from public.ripening_inventory_available() where container_id='53500000-0000-0000-0000-000000000001'),4::numeric,'partial reservation leaves four kg');
select is((select allocated_weight_kg::numeric from public.orders where id='53300000-0000-0000-0000-000000000001'),2::numeric,'order aggregate updated');
select set_config('test.history_count',(select count(*)::text from public.change_history),true);
select is(public.ripening_plan_register(pg_temp.req(current_setting('test.input')::jsonb,
 '53600000-0000-4000-8000-000000000001'))->>'idempotent_replay','true','duplicate request replays');
select is((select count(*) from public.change_history),current_setting('test.history_count')::bigint,'replay does not add history');
select is(public.ripening_plan_register(pg_temp.req(pg_temp.plan_input(),
 '53600000-0000-4000-8000-000000000001'))->'error'->>'code','IDEMPOTENCY_KEY_REUSED','key reuse rejected');
select is(public.ripening_plan_register(pg_temp.req(pg_temp.plan_input(5)))->'error'->>'code','INVENTORY_UNAVAILABLE','second plan cannot overbook');
select is((select count(*) from public.ripening_lots where display_id like '追熟-2027-%'),1::bigint,'failed plan rolled back');
select is(public.ripening_plan_update(pg_temp.req(pg_temp.plan_input()||pg_temp.transition_input()||'{"expected_version":99}'))->'error'->>'code','CONFLICT_STALE','stale version rejected');

select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
select is(current_setting('test.plan')::jsonb->'data'->>'status','confirmed','balanced plan confirms');
select is(current_setting('test.plan')::jsonb->'data'->>'version','2','confirmation increments version');
select is(public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))->'error'->>'code','CONFLICT_STALE','confirmed plan cannot confirm twice');

select set_config('test.plan',public.ripening_plan_update(pg_temp.req(pg_temp.plan_input(7)||pg_temp.transition_input()))::text,true);
select is(current_setting('test.plan')::jsonb->'data'->>'status','draft','change returns confirmed plan to draft');
select is(current_setting('test.plan')::jsonb->'data'->>'needs_review','true','change requires review');
select is(current_setting('test.plan')::jsonb->'data'->>'use_type','reserve','replacement derives reserve');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),7::numeric,'same container replacement counts once');
select is((select allocated_weight_kg::numeric from public.orders where id='53300000-0000-0000-0000-000000000001'),0::numeric,'replacement releases former orders');
select is(public.ripening_plan_update(pg_temp.req(pg_temp.plan_input(11)||pg_temp.transition_input()))->'error'->>'code','INVENTORY_UNAVAILABLE','invalid replacement rejected atomically');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),7::numeric,'failed replacement retains old reservation');

select set_config('test.plan',public.ripening_plan_update(pg_temp.req(pg_temp.plan_input(7)||pg_temp.transition_input()||'{"allocations":[]}'))::text,true);
select is(public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))->'error'->>'code','RIPENING_WEIGHT_MISMATCH','incomplete allocation cannot confirm');
select set_config('test.plan',public.ripening_plan_update(pg_temp.req(pg_temp.plan_input(7)||pg_temp.transition_input()||'{"reservations":[]}'))::text,true);
select is(public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))->'error'->>'code','RIPENING_WEIGHT_MISMATCH','incomplete reservation cannot confirm');
select set_config('test.plan',public.ripening_plan_update(pg_temp.req(pg_temp.plan_input(7)||pg_temp.transition_input()))::text,true);
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
select set_config('test.cancel_input',pg_temp.transition_input()::text,true);
select set_config('test.plan',public.ripening_plan_cancel(pg_temp.req(pg_temp.transition_input(),
 '53600000-0000-4000-8000-000000000002'))::text,true);
select is(current_setting('test.plan')::jsonb->'data'->>'status','cancelled','confirmed plan cancels before work');
select is(current_setting('test.plan')::jsonb->'data'->'reservations'->0->>'status','released','released reservation retained');
select is((select available_weight_kg from public.ripening_inventory_available() where container_id='53500000-0000-0000-0000-000000000001'),10::numeric,'cancel restores availability');
select is(public.ripening_plan_cancel(pg_temp.req(current_setting('test.cancel_input')::jsonb,
 '53600000-0000-4000-8000-000000000002'))->>'idempotent_replay','true','cancel replay safe');

select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000003',true);
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(pg_temp.plan_input()))::text,true);
select is(current_setting('test.plan')::jsonb->>'ok','true','administrator creates plan');
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
reset role;
update public.ripening_lots set status='in_progress' where id=(current_setting('test.plan')::jsonb->'data'->>'id')::uuid;
set local role authenticated;
select is(public.ripening_plan_cancel(pg_temp.req(pg_temp.transition_input()))->'error'->>'code','CONFLICT_STALE','started plan cannot release reservations');
select is(public.ripening_plan_update(pg_temp.req(pg_temp.plan_input()||pg_temp.transition_input()))->'error'->>'code','CONFLICT_STALE','started plan cannot change');
select is((select reserved_weight_kg::numeric from public.containers where id='53500000-0000-0000-0000-000000000001'),6::numeric,'started plan retains reservation');
select ok(exists(select 1 from public.change_history where entity_type='inventory_reservation' and operation='transition'),'reservation transition audited');
select ok(exists(select 1 from public.change_history where entity_type='ripening_allocation' and operation='delete' and after_data->>'deleted'='true'),'deleted allocations audited');
select ok(exists(select 1 from public.change_history where entity_type='order' and operation='update'),'order aggregate audited');
reset role;
select ok(not has_function_privilege('anon','public.ripening_plan_register(jsonb)','execute'),'anon cannot execute');
select ok(not has_function_privilege('authenticated','private.ripening_plan_action(text,jsonb,uuid,uuid)','execute'),'private action inaccessible');
select * from finish();
rollback;
