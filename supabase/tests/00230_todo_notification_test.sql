begin;
select no_plan();
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) values
('dd150000-0000-4000-8000-000000000001','authenticated','authenticated','todo-admin@example.test','{"provider":"google","providers":["google"]}','{"full_name":"Demo Admin"}'),
('dd150000-0000-4000-8000-000000000002','authenticated','authenticated','todo-member@example.test','{"provider":"google","providers":["google"]}','{"full_name":"Demo Member"}');
select private.set_user_access('dd150000-0000-4000-8000-000000000001','active',array['administrator']);
select private.set_user_access('dd150000-0000-4000-8000-000000000002','active',array['member']);
select ok(not has_function_privilege('authenticated','public.todo_notification_begin(text,text,uuid)','execute'),'clients cannot claim notifications');
select ok(not has_function_privilege('anon','public.todo_notification_finish(uuid,text,integer,text)','execute'),'anonymous cannot forge results');
select throws_ok($$select public.todo_notification_begin('test-member','manual','dd150000-0000-4000-8000-000000000002')$$,'42501','Administrator required','member rejected');
select is(public.todo_notification_begin('test-first','manual','dd150000-0000-4000-8000-000000000001')->>'claimed','true','admin can claim');
select is(public.todo_notification_begin('test-first','manual','dd150000-0000-4000-8000-000000000001')->>'claimed','false','duplicate cannot send');
select is(public.todo_notification_begin('test-second','manual','dd150000-0000-4000-8000-000000000001')->>'status','rate_limited','manual cooldown is global');
select is(public.todo_notification_begin('daily:'||(now() at time zone 'Asia/Tokyo')::date::text,'daily',null)->>'claimed','true','daily is independent of manual cooldown');
select is(public.todo_notification_begin('daily:'||(now() at time zone 'Asia/Tokyo')::date::text,'daily',null)->>'claimed','false','daily at most once per Japan day');
select public.todo_notification_finish((select id from private.todo_notifications where request_key='test-first'),'sent',2,null);
select is((select status from private.todo_notifications where request_key='test-first'),'sent','successful result recorded');
select public.todo_notification_finish((select id from private.todo_notifications where request_key='test-first'),'failed',2,'DISCORD_REJECTED');
select is((select status from private.todo_notifications where request_key='test-first'),'sent','terminal result cannot be overwritten');
select is((select schedule from cron.job where jobname='daily-todo-discord'),'0 23 * * *','08:00 Japan scheduled in UTC');
select * from finish();
rollback;
