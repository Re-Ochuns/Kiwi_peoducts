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
from generate_series(1,3) n;

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

create function pg_temp.req(v jsonb,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select jsonb_build_object('meta',jsonb_build_object('idempotency_key',k,'correlation_id',gen_random_uuid()),'input',v);
$$;
create function pg_temp.input(amount numeric default 2,ord uuid default '53300000-0000-0000-0000-000000000001',
 cont uuid default '64100000-0000-0000-0000-000000000001') returns jsonb language sql as $$
 select jsonb_build_object('order_id',ord,'expected_order_version',(select version from public.orders where id=ord),
 'worker_id','a7000000-0000-0000-0000-000000000001','checked',true,'reason','出荷テスト',
 'lines',jsonb_build_array(jsonb_build_object('container_id',cont,'expected_version',(select version from public.containers where id=cont),'shipped_weight_kg',amount)));
$$;
create function pg_temp.cancel(v jsonb) returns jsonb language sql as $$
 select pg_temp.req(jsonb_build_object('shipment_id',v->'data'->>'id','expected_version',v->'data'->'version','reason','取消テスト'));
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000002',true);
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()))->'error'->>'code','AUTH_FORBIDDEN','pending denied');
select is(public.shipment_inventory_list(),'[]'::jsonb,'pending inventory hidden');
select set_config('request.jwt.claim.sub','',true);
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()))->'error'->>'code','AUTH_REQUIRED','anonymous denied');
select set_config('request.jwt.claim.sub','53000000-0000-0000-0000-000000000001',true);
select throws_ok($$select private.shipped_weight('53300000-0000-0000-0000-000000000001')$$,'42501',null,'private helper denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()||'{"checked":false}'))->'error'->>'code','CONFIRMATION_REQUIRED','confirmation required');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input(0)))->'error'->>'code','VALIDATION_FAILED','zero denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input(0.001)))->'error'->>'code','VALIDATION_FAILED','precision denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()||'{"lines":[]}'))->'error'->>'code','VALIDATION_FAILED','empty lines denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()||jsonb_build_object('lines',(pg_temp.input()->'lines')||(pg_temp.input()->'lines'))))->'error'->>'code','VALIDATION_FAILED','duplicate container denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()||'{"expected_order_version":99}'))->'error'->>'code','CONFLICT_STALE','stale order denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input(7)))->'error'->>'code','ORDER_WEIGHT_EXCEEDED','over order denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()||jsonb_build_object('shipped_at',now()+interval '1 day')))->'error'->>'code','VALIDATION_FAILED','future date denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input()||'{"lines":[1]}'))->'error'->>'code','VALIDATION_FAILED','scalar line denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input(5,'53300000-0000-0000-0000-000000000001','64100000-0000-0000-0000-000000000002')))->'error'->>'code','INVENTORY_UNAVAILABLE','over container denied');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input(1,'53300000-0000-0000-0000-000000000003')))->'error'->>'code','ALLOCATION_UNAVAILABLE','cannot consume another order allocation');
select is(public.shipment_confirm(pg_temp.req(jsonb_set(pg_temp.input(),'{lines,0,expected_version}','99')))->'error'->>'code','CONFLICT_STALE','stale container denied');
select is((select count(*) from public.shipments),0::bigint,'rejected requests leave no shipment');
select set_config('test.req',pg_temp.req(jsonb_set(pg_temp.input(),'{lines,0,container_id}', '" 64100000-0000-0000-0000-000000000001 "'))::text,true);
select set_config('test.s1',public.shipment_confirm(current_setting('test.req')::jsonb)::text,true);
select is(current_setting('test.s1')::jsonb->>'ok','true','partial shipment succeeds');
select is((select current_weight_kg::numeric from public.containers where display_id='SHIP64-C1'),6::numeric,'stock reduced on same container');
select is((select status from public.orders where order_number='PLAN53-1'),'partially_shipped','partial order');
select is(public.shipment_confirm(current_setting('test.req')::jsonb)->>'idempotent_replay','true','same key replays');
select is((select count(*) from public.inventory_events where event_type='shipment'),1::bigint,'replay adds no ledger');
select is(public.shipment_confirm(jsonb_set(current_setting('test.req')::jsonb,'{input,reason}','"different"'))->'error'->>'code','IDEMPOTENCY_KEY_REUSED','key payload reuse denied');
reset role;
select is((select count(*) from public.change_history where entity_type='container' and correlation_id=(current_setting('test.req')::jsonb->'meta'->>'correlation_id')::uuid),1::bigint,'container audit correlation');
select is((select count(*) from public.change_history where entity_type in ('shipment','shipment_line','inventory_event') and reason='出荷テスト' and correlation_id=(current_setting('test.req')::jsonb->'meta'->>'correlation_id')::uuid),3::bigint,'all shipment records retain reason and correlation');
set local role authenticated;
select set_config('test.s2',public.shipment_confirm(pg_temp.req(pg_temp.input(4)))::text,true);
select is(current_setting('test.s2')::jsonb->>'ok','true','second shipment succeeds');
select is((select status from public.orders where order_number='PLAN53-1'),'shipped','fully shipped order');
select is((select count(*) from public.shipment_list('53300000-0000-0000-0000-000000000001')),2::bigint,'two shipments for one order');
select is((select status from public.work_tasks where order_id='53300000-0000-0000-0000-000000000001'),'completed','shipping task completed');
select set_config('test.s3',public.shipment_confirm(pg_temp.req(pg_temp.input(4,'53300000-0000-0000-0000-000000000002','64100000-0000-0000-0000-000000000002')))::text,true);
select is(current_setting('test.s3')::jsonb->>'ok','true','other allocated order ships');
select is((select status from public.containers where display_id='SHIP64-C2'),'shipped','empty container shipped');
select is(public.shipment_inventory_list()->0->>'remaining_use_type','reserve','remaining stock becomes reserve');
select is((select allocated_weight_kg::numeric from public.ripening_allocations where order_id='53300000-0000-0000-0000-000000000001'),6::numeric,'planned allocation preserved');
select set_config('test.cancel',pg_temp.cancel(current_setting('test.s2')::jsonb)::text,true);
select is(public.shipment_cancel(current_setting('test.cancel')::jsonb)->>'ok','true','cancel succeeds');
select is((select current_weight_kg::numeric from public.containers where display_id='SHIP64-C1'),6::numeric,'cancel restores stock');
select is((select status from public.orders where order_number='PLAN53-1'),'partially_shipped','cancel restores partial order');
select is((select status from public.work_tasks where order_id='53300000-0000-0000-0000-000000000001'),'pending','task reopens');
select is(public.shipment_inventory_list()->0->>'remaining_use_type','mixed','cancel restores allocation classification');
select is(public.shipment_cancel(current_setting('test.cancel')::jsonb)->>'idempotent_replay','true','cancel replay');
select is(public.shipment_cancel(pg_temp.cancel(current_setting('test.s2')::jsonb))->'error'->>'code','SHIPMENT_UNAVAILABLE','new-key double cancel denied');
select is((select count(*) from public.inventory_events where reverses_event_id is not null),1::bigint,'one reversal');
select is(public.shipment_cancel(pg_temp.cancel(current_setting('test.s1')::jsonb))->>'ok','true','cancel last shipment');
select is((select status from public.orders where order_number='PLAN53-1'),'in_progress','no shipments restores in-progress');
reset role;
update public.containers set shippable_until=now()-interval '2 days',best_before_at=now()-interval '1 day' where display_id='SHIP64-C2';
set local role authenticated;
select is(public.shipment_cancel(pg_temp.cancel(current_setting('test.s3')::jsonb))->>'ok','true','expired shipment reversal allowed');
select is((select status from public.containers where display_id='SHIP64-C2'),'expired','reversal does not make expired stock usable');
select is(public.shipment_confirm(pg_temp.req(pg_temp.input(2,'53300000-0000-0000-0000-000000000002','64100000-0000-0000-0000-000000000002')))->'error'->>'code','CONTAINER_EXPIRED','expired stock denied');
set constraints all immediate;
select * from finish();
rollback;
