begin;
select no_plan();
select is((select ethylene_processing_hours from private.work_task_settings where singleton),168::numeric,'farm default is one week');
insert into auth.users(id,email,raw_user_meta_data) values
 ('53000000-0000-0000-0000-000000000001','plan-member@example.com','{}'),
 ('53000000-0000-0000-0000-000000000002','plan-pending@example.com','{}'),
 ('53000000-0000-0000-0000-000000000003','plan-admin@example.com','{}');
select private.set_user_access('53000000-0000-0000-0000-000000000001','active',array['member']);
select private.set_user_access('53000000-0000-0000-0000-000000000003','active',array['administrator']);
insert into public.ripening_rules(harvest_year,harvest_month,variety_id,ethylene_temperature,
 ethylene_hours,rest_temperature,rest_days,shippable_days,best_before_days)
values(2000,5,'a1000000-0000-0000-0000-000000000001',20,168,15,3,5,7);
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

set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select set_config('test.register_input',pg_temp.req(pg_temp.plan_input())::text,true);
select set_config('test.plan',public.ripening_plan_register(current_setting('test.register_input')::jsonb)::text,true);
select is((select count(*) from public.work_tasks),0::bigint,'draft does not generate executable tasks');
select set_config('test.confirm_input',pg_temp.req(pg_temp.transition_input())::text,true);
select set_config('test.plan',public.ripening_plan_confirm(current_setting('test.confirm_input')::jsonb)::text,true);
select is(current_setting('test.plan')::jsonb->>'ok','true','plan confirms with task generation');
select is((select count(*) from public.work_tasks),3::bigint,'confirmation creates all three ripening tasks');
select is((select scheduled_at from public.work_tasks where task_type='ethylene_removal_check'),
 '2027-05-17 00:00+00'::timestamptz,'removal uses configured duration');
select is(current_setting('test.plan')::jsonb->'data'->'master_snapshot'->>'ethylene_hours','168','processing hours are snapshotted');
select ok(not exists(select 1 from public.work_tasks where calendar_event_id is null),'stable event IDs assigned before external I/O');
select ok(not exists(select 1 from public.work_tasks where task_details ? 'customer_name' or task_details ? 'address'),'task payload excludes customer PII');
select ok(not exists(select 1 from public.work_tasks where target_url not like '/work-tasks/%'),'tasks carry target links');
select is(public.ripening_plan_confirm(current_setting('test.confirm_input')::jsonb)->>'idempotent_replay','true','confirmation replay');
select is((select count(*) from public.work_tasks),3::bigint,'replay does not duplicate tasks');
select throws_ok($$select public.calendar_sync_claim(5)$$,'42501',null,'members cannot claim worker jobs');
select is(public.work_task_sync_warnings()->>'pending_count','3','unsent tasks are visible as pending');

reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('test.jobs',public.calendar_sync_claim(5)::text,true);
select is(jsonb_array_length(current_setting('test.jobs')::jsonb),3,'worker claims tasks');
select is(jsonb_array_length(public.calendar_sync_claim(5)),0,'another worker cannot claim leased jobs');
select set_config('test.job',(current_setting('test.jobs')::jsonb->0)::text,true);
select ok(public.calendar_sync_finish(
 (current_setting('test.job')::jsonb->'task'->>'id')::uuid,
 (current_setting('test.job')::jsonb->>'lease_token')::uuid,1,'GOOGLE_RATE_LIMIT'),'failure acknowledged');
select is((select calendar_sync_status from public.work_tasks where id=(current_setting('test.job')::jsonb->'task'->>'id')::uuid),'failed','failed state visible');
select is((select status from public.ripening_lots where id=(current_setting('test.plan')::jsonb->'data'->>'id')::uuid),'confirmed','external failure does not roll back confirmation');
select is(jsonb_array_length(public.calendar_sync_claim(5)),0,'retry respects backoff');
reset role;
select cmp_ok((select next_attempt_at from private.calendar_sync_jobs where task_id=(current_setting('test.job')::jsonb->'task'->>'id')::uuid),'>',now(),'retry scheduled in future');
update private.calendar_sync_jobs set next_attempt_at=now() where task_id=(current_setting('test.job')::jsonb->'task'->>'id')::uuid;
set local role service_role;
select set_config('test.retry',(public.calendar_sync_claim(5)->0)::text,true);
select is(current_setting('test.retry')::jsonb->'task'->>'calendar_event_id',current_setting('test.job')::jsonb->'task'->>'calendar_event_id','retry uses same event ID');
select ok(public.calendar_sync_finish(
 (current_setting('test.retry')::jsonb->'task'->>'id')::uuid,
 (current_setting('test.retry')::jsonb->>'lease_token')::uuid,1,null),'successful retry acknowledged');
select is((select calendar_sync_status from public.work_tasks where id=(current_setting('test.retry')::jsonb->'task'->>'id')::uuid),'synced','success clears warning');
reset role;
select is((select next_attempt_at from private.calendar_sync_jobs where task_id=(current_setting('test.retry')::jsonb->'task'->>'id')::uuid),now()+interval '15 minutes','successful tasks periodically reapply app values');
select is((select count(*) from private.calendar_sync_log),2::bigint,'attempt outcomes logged');

update private.work_task_settings set ethylene_processing_hours=24;
-- Existing confirmed plans keep their snapshotted 168-hour duration.
-- Edit while two old task revisions are still leased.
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select set_config('test.plan',public.ripening_plan_update(pg_temp.req(pg_temp.plan_input()||pg_temp.transition_input()||
 '{"planned_ethylene_at":"2027-05-12T09:00:00+09:00"}'))::text,true);
select is((select count(*) from public.work_tasks where status='cancelled'),3::bigint,'editing confirmed plan cancels old task schedules pending reconfirmation');
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('test.stale',(current_setting('test.jobs')::jsonb->1)::text,true);
select ok(not public.calendar_sync_finish(
 (current_setting('test.stale')::jsonb->'task'->>'id')::uuid,
 (current_setting('test.stale')::jsonb->>'lease_token')::uuid,1,null),'stale result cannot mark a changed task synced');
select is((select calendar_sync_status from public.work_tasks where id=(current_setting('test.stale')::jsonb->'task'->>'id')::uuid),'pending','new revision stays pending');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
select is((select count(*) from public.work_tasks),3::bigint,'reconfirmation reuses task identities');
select is((select count(*) from public.work_tasks where status='pending'),3::bigint,'reconfirmation activates tasks');
select is((select scheduled_at from public.work_tasks where task_type='ethylene_removal_check'),
 '2027-05-19 00:00+00'::timestamptz,'changed injection schedule shifts removal');
select set_config('test.plan',public.ripening_plan_cancel(pg_temp.req(pg_temp.transition_input()))::text,true);
select is((select count(*) from public.work_tasks where status='cancelled'),3::bigint,'plan cancellation keeps cancelled tasks');
reset role;
select ok(exists(select 1 from public.change_history where entity_type='work_task' and operation='transition' and after_data->>'status'='cancelled'),'cancellation history retained');

-- Orders get independent shipping tasks with no customer or address payload.
reset role;
update public.orders set status='draft' where id='53300000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000003',true);
select is(public.order_confirm(pg_temp.req('{"order_id":"53300000-0000-0000-0000-000000000001","expected_version":1,"reason":"confirm"}'))->>'ok','true','order confirms');
select is((select count(*) from public.work_tasks where task_type='shipping'),1::bigint,'order confirmation creates shipping task');
select is((select task_details->>'shipping_date' from public.work_tasks where task_type='shipping'),'2027-06-01','shipping preserves local date');
select is(public.order_cancel(pg_temp.req('{"order_id":"53300000-0000-0000-0000-000000000001","expected_version":2,"reason":"cancel"}'))->>'ok','true','order cancels');
select is((select status from public.work_tasks where task_type='shipping'),'cancelled','shipping cancellation synchronized');

select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.work_task_list()),0::bigint,'pending account sees no tasks');
reset role;
select ok(not has_function_privilege('anon','public.calendar_sync_claim(integer)','execute'),'anon cannot claim');
select ok(not has_function_privilege('authenticated','public.calendar_sync_finish(uuid,uuid,bigint,text)','execute'),'users cannot forge sync success');
select ok(has_function_privilege('service_role','public.calendar_sync_finish(uuid,uuid,bigint,text)','execute'),'service role may acknowledge');
select lives_ok('select private.dispatch_calendar_sync()','unconfigured dispatcher makes no external request');

-- Expired worker leases recover; a superseded worker cannot acknowledge.
update private.calendar_sync_jobs set lease_until=now()-interval '1 second' where lease_token is not null;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('test.recovered',public.calendar_sync_claim(5)::text,true);
select cmp_ok(jsonb_array_length(current_setting('test.recovered')::jsonb),'>',0,'expired leases can be claimed');
select ok(not public.calendar_sync_finish(
 (current_setting('test.stale')::jsonb->'task'->>'id')::uuid,
 (current_setting('test.stale')::jsonb->>'lease_token')::uuid,1,null),'superseded worker cannot acknowledge');
select set_config('test.gone',(current_setting('test.recovered')::jsonb->0)::text,true);
select ok(public.calendar_sync_finish(
 (current_setting('test.gone')::jsonb->'task'->>'id')::uuid,
 (current_setting('test.gone')::jsonb->>'lease_token')::uuid,
 (current_setting('test.gone')::jsonb->>'revision')::bigint,'GOOGLE_EVENT_GONE'),'deleted remote event schedules replacement');
select isnt((select calendar_event_id from public.work_tasks where id=(current_setting('test.gone')::jsonb->'task'->>'id')::uuid),
 current_setting('test.gone')::jsonb->'task'->>'calendar_event_id','tombstone recovery uses a new generation ID');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select is(public.work_tasks_reconcile(pg_temp.req('{"reason":"migration"}'))->'error'->>'code','AUTH_FORBIDDEN','only administrators can reconcile old plans');
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000003',true);
select set_config('test.reconcile',pg_temp.req('{"reason":"migration"}')::text,true);
select is(public.work_tasks_reconcile(current_setting('test.reconcile')::jsonb)->>'ok','true','administrator reconciles legacy sources');
select is((select count(*) from public.work_tasks where task_type='shipping'),2::bigint,'legacy confirmed order receives its missing shipping task');
select is(public.work_tasks_reconcile(current_setting('test.reconcile')::jsonb)->>'idempotent_replay','true','reconciliation is idempotent');
select ok(public.work_task_get((select id from public.work_tasks limit 1)) is not null,'active users can read task details');
reset role;

select * from finish();
rollback;
