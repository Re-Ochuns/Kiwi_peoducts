begin;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
 ('59000000-0000-0000-0000-000000000001','board118-member@example.com','{}'),
 ('59000000-0000-0000-0000-000000000002','board118-pending@example.com','{}'),
 ('59000000-0000-0000-0000-000000000003','board118-admin@example.com','{}');
select private.set_user_access('59000000-0000-0000-0000-000000000001','active',array['member']);
select private.set_user_access('59000000-0000-0000-0000-000000000003','active',array['administrator']);
insert into public.ripening_rules(harvest_year,harvest_month,variety_id,ethylene_temperature,
 ethylene_hours,rest_temperature,rest_days,shippable_days,best_before_days)
values(2000,5,'a1000000-0000-0000-0000-000000000001',20,168,15,3,5,7)
on conflict do nothing;
update public.ripening_rules set ethylene_hours=168,rest_days=3,shippable_days=5,best_before_days=7
where variety_id='a1000000-0000-0000-0000-000000000001' and harvest_month=5 and is_active;
insert into public.customers(id,customer_code,name,postal_code,address)
values('59100000-0000-0000-0000-000000000001','PLAN59','Dummy','000','Dummy');
insert into public.shipping_destinations(id,customer_id,destination_name,recipient_name,postal_code,address)
values('59200000-0000-0000-0000-000000000001','59100000-0000-0000-0000-000000000001','Dummy','Dummy','000','Dummy');
insert into public.orders(id,order_number,customer_id,shipping_destination_id,ordered_on,scheduled_ship_on,
 variety_id,grade_id,ordered_weight_kg,shipping_destination_snapshot,status)
select ('59300000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'PLAN59-'||n,
 '59100000-0000-0000-0000-000000000001','59200000-0000-0000-0000-000000000001','2027-05-01','2027-06-01',
 'a1000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000005',10,'{}','confirmed'
from generate_series(1,2) n;
insert into public.receiving_lots
select (jsonb_populate_record(null::public.receiving_lots,to_jsonb(r)||
 '{"id":"59600000-0000-0000-0000-000000000001","display_id":"BOARD118-RECEIVING"}'::jsonb)).*
from public.receiving_lots r where id='aa000000-0000-0000-0000-000000000001';
insert into public.sorting_results(id,display_id,receiving_lot_id,sorted_on,sorted_by,input_weight_kg,output_weight_kg,loss_weight_kg)
values('59400000-0000-0000-0000-000000000001','PLAN59-S','59600000-0000-0000-0000-000000000001',
 '2027-05-03','a7000000-0000-0000-0000-000000000001',48.25,10,38.25);
insert into public.containers(id,display_id,sorting_result_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,location_id)
values('59500000-0000-0000-0000-000000000001','PLAN59-C','59400000-0000-0000-0000-000000000001',
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
 'reservations',jsonb_build_array(jsonb_build_object('container_id','59500000-0000-0000-0000-000000000001','reserved_weight_kg',weight_value)));
$$;
create function pg_temp.transition_input() returns jsonb language sql as $$
select jsonb_build_object('ripening_lot_id',current_setting('test.plan')::jsonb->'data'->>'id',
 'expected_version',(current_setting('test.plan')::jsonb->'data'->>'version')::bigint,'reason','test');
$$;

select set_config('request.jwt.claim.sub','59000000-0000-0000-0000-000000000003',true);
create function pg_temp.criteria() returns jsonb language sql as $$
 select jsonb_build_object('scheduled_ship_date','2027-06-01',
  'variety_id','a1000000-0000-0000-0000-000000000001',
  'grade_id','a2000000-0000-0000-0000-000000000005','ordered_weight_kg',2);
$$;
create function pg_temp.board_input(candidate jsonb) returns jsonb language sql as $$
 select pg_temp.criteria()||jsonb_build_object(
  'candidate_kind',candidate->'kind','candidate_id',candidate->'id','candidate_version',candidate->'version',
  'customer_id','59100000-0000-0000-0000-000000000001',
  'shipping_destination_id','59200000-0000-0000-0000-000000000001',
  'storage_location_id','a8000000-0000-0000-0000-000000000001',
  'assigned_worker_id','a7000000-0000-0000-0000-000000000001');
$$;
select set_config('test.candidate',(select value::text from jsonb_array_elements(
 public.board_order_candidates(pg_temp.criteria())) where value->>'id'='59500000-0000-0000-0000-000000000001'),true);
select is(current_setting('test.candidate')::jsonb->>'kind','container','cold source is eligible');
select is(current_setting('test.candidate')::jsonb->>'use_type','unassigned','free cold stock remains unassigned');
select is((current_setting('test.candidate')::jsonb->>'available_weight_kg')::numeric,10::numeric,'candidate uses free weight');
select is(jsonb_array_length(public.board_order_candidates(pg_temp.criteria()||'{"ordered_weight_kg":99999}')),0,'insufficient weight excluded');
select is(jsonb_array_length(public.board_order_candidates(pg_temp.criteria()||'{"grade_id":"a2000000-0000-0000-0000-000000000001"}')),0,'grade mismatch excluded');
savepoint candidate_rules;
update public.ripening_rules set is_active=false where variety_id='a1000000-0000-0000-0000-000000000001' and harvest_month=5;
select is((select count(*) from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria())) where value->>'id'='59500000-0000-0000-0000-000000000001'),0::bigint,'missing active rule excludes cold inventory');
rollback to candidate_rules;
savepoint candidate_review;
update public.containers set needs_review=true where id='59500000-0000-0000-0000-000000000001';
select is((select count(*) from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria())) where value->>'id'='59500000-0000-0000-0000-000000000001'),0::bigint,'review-required inventory is excluded');
rollback to candidate_review;
select set_config('test.count',(select count(*)::text from public.orders),true);
select set_config('test.bad',public.board_order_confirm(pg_temp.req(
 pg_temp.board_input(current_setting('test.candidate')::jsonb)||'{"assigned_worker_id":"59000000-0000-0000-0000-000000000002"}'))::text,true);
select is(current_setting('test.bad')::jsonb->>'ok','false','invalid worker rejects entire transaction');
select is((select count(*)::text from public.orders),current_setting('test.count'),'order creation rolled back when plan fails');
select set_config('test.req',pg_temp.req(pg_temp.board_input(current_setting('test.candidate')::jsonb))::text,true);
select set_config('test.board',public.board_order_confirm(current_setting('test.req')::jsonb)::text,true);
select is(current_setting('test.board')::jsonb->>'ok','true','atomic order and plan succeeds');
select is((select status from public.orders where id=(current_setting('test.board')::jsonb->'data'->>'order_id')::uuid),'confirmed','order confirmed');
select is((select status from public.ripening_lots where id=(current_setting('test.board')::jsonb->'data'->>'ripening_lot_id')::uuid),'confirmed','plan confirmed');
select is((select current_weight_kg::numeric from public.containers where id='59500000-0000-0000-0000-000000000001'),10::numeric,'reservation does not consume physical stock');
select is((select reserved_weight_kg::numeric from public.containers where id='59500000-0000-0000-0000-000000000001'),2::numeric,'exact order weight reserved');
select is(public.board_order_confirm(current_setting('test.req')::jsonb)->>'idempotent_replay','true','retry is idempotent');
select is(public.board_order_confirm(pg_temp.req(pg_temp.board_input(current_setting('test.candidate')::jsonb)))->'error'->>'code','INVENTORY_UNAVAILABLE','stale availability rejected');
select set_config('test.plan',public.ripening_plan_register(pg_temp.req(pg_temp.plan_input(6)))::text,true);
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
-- This plan completes 2027-05-20 and expires before June 1; it must be excluded.
select is((select count(*) from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria()))
 where value->>'id'=current_setting('test.plan')::jsonb->'data'->>'id'),0::bigint,'lot expiring before shipment excluded');
-- Shift the persisted plan to a viable date through the ordinary update RPC.
select set_config('test.plan',public.ripening_plan_update(pg_temp.req(pg_temp.plan_input(6)||
 jsonb_build_object('ripening_lot_id',current_setting('test.plan')::jsonb->'data'->'id',
 'expected_version',current_setting('test.plan')::jsonb->'data'->'version',
 'planned_ethylene_at','2027-05-22T09:00:00+09:00','planned_completion_at','2027-06-01T09:00:00+09:00','reason','test')))::text,true);
select set_config('test.plan',public.ripening_plan_confirm(pg_temp.req(pg_temp.transition_input()))::text,true);
select set_config('test.lot',(current_setting('test.plan')::jsonb->'data'->>'id'),true);
savepoint confirmed_source;
update public.containers set needs_review=true where id='59500000-0000-0000-0000-000000000001';
select is((select count(*) from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria())) where value->>'id'=current_setting('test.lot')),0::bigint,'confirmed plan with invalid source is excluded');
rollback to confirmed_source;

select set_config('test.candidate',(select value::text from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria()))
 where value->>'id'=current_setting('test.lot')),true);
select set_config('test.board',public.board_order_confirm(pg_temp.req(pg_temp.board_input(current_setting('test.candidate')::jsonb)))::text,true);
select is(current_setting('test.board')::jsonb->>'ok','true','existing reserve lot accepts an order');
select is(current_setting('test.board')::jsonb->'data'->>'ripening_lot_id',current_setting('test.lot'),'existing lot is reused');
select is((select sum(allocated_weight_kg)::numeric from public.ripening_allocations
 where ripening_lot_id=current_setting('test.lot')::uuid and allocation_type='reserve'),4::numeric,'reserve reduced by order weight');
select is((select status from public.ripening_lots where id=current_setting('test.lot')::uuid),'confirmed','lot state preserved');
select is((select value->>'stage' from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria())) where value->>'id'=current_setting('test.lot')),'waiting','confirmed plan appears in waiting column');
select is((select value->>'use_type' from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria())) where value->>'id'=current_setting('test.lot')),'mixed','sorted mixed lot keeps its order status in candidates');
select is((select count(*) from private.board_order_transfer),0::bigint,'transfer gate cleaned up');
select throws_ok(format('update public.ripening_allocations set allocated_weight_kg=1 where ripening_lot_id=%L and allocation_type=%L',current_setting('test.lot'),'reserve'),
 '23514','ripening allocations can only change while lot is draft','ordinary post-confirmation edits remain forbidden');
-- Started lot: allocation transfer must not reset execution or create a new plan.
update public.ripening_lots set status='in_progress' where id=current_setting('test.lot')::uuid;
update public.inventory_reservations set status='consumed',consumed_at=now() where ripening_lot_id=current_setting('test.lot')::uuid;
insert into public.containers(display_id,ripening_lot_id,variety_id,grade_id,original_weight_kg,current_weight_kg,status,location_id)
 values('BOARD118-OUTPUT',current_setting('test.lot')::uuid,'a1000000-0000-0000-0000-000000000001',
 'a2000000-0000-0000-0000-000000000005',6,6,'ethylene_processing','a8000000-0000-0000-0000-000000000001');
select set_config('test.candidate',(select value::text from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria()))
 where value->>'id'=current_setting('test.lot')),true);
select set_config('test.board',public.board_order_confirm(pg_temp.req(pg_temp.board_input(current_setting('test.candidate')::jsonb)))::text,true);
select is(current_setting('test.board')::jsonb->>'ok','true','started lot accepts reserve transfer');
select is((select status from public.ripening_lots where id=current_setting('test.lot')::uuid),'in_progress','started lot remains in progress');
select is((select status from public.orders where id=(current_setting('test.board')::jsonb->'data'->>'order_id')::uuid),'in_progress','new order reflects existing work');
select is((select sum(allocated_weight_kg)::numeric from public.ripening_allocations
 where ripening_lot_id=current_setting('test.lot')::uuid and allocation_type='reserve'),2::numeric,'started reserve reduced exactly once');
select is((select count(*) from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria()||'{"scheduled_ship_date":"2027-06-06"}')) where value->>'id'=current_setting('test.lot')),0::bigint,'shipment exactly at expiration is excluded');
select is((select count(*) from jsonb_array_elements(public.board_order_candidates(pg_temp.criteria()||'{"scheduled_ship_date":"2027-05-31"}')) where value->>'id'=current_setting('test.lot')),0::bigint,'shipment before completion is excluded');
select set_config('request.jwt.claim.sub','59000000-0000-0000-0000-000000000001',true);
select is(public.board_order_confirm(current_setting('test.req')::jsonb)->'error'->>'code','AUTH_FORBIDDEN','member cannot submit even a replay');
select throws_ok('select public.board_order_candidates(pg_temp.criteria())','42501','管理者だけが候補を検索できます。','member cannot search');
select * from finish();
rollback;
