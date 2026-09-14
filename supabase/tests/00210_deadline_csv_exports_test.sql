begin;
select no_plan();

insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
values
 ('96000000-0000-4000-8000-000000000001','authenticated','authenticated','csv96-admin@example.com','{"provider":"google","providers":["google"]}','{"full_name":"CSV96 Admin"}'),
 ('96000000-0000-4000-8000-000000000002','authenticated','authenticated','csv96-member@example.com','{"provider":"google","providers":["google"]}','{"full_name":"CSV96 Member"}'),
 ('96000000-0000-4000-8000-000000000003','authenticated','authenticated','csv96-pending@example.com','{"provider":"google","providers":["google"]}','{"full_name":"CSV96 Pending"}');
select private.set_user_access('96000000-0000-4000-8000-000000000001','active',array['administrator']);
select private.set_user_access('96000000-0000-4000-8000-000000000002','active',array['member']);
insert into public.varieties(id,code,name)
values ('96000000-0000-4000-8000-000000000010','CSV96-KIWI','CSV96品種');
insert into public.ripening_rules(id,harvest_year,harvest_month,variety_id,
  ethylene_temperature,ethylene_hours,rest_temperature,rest_days,shippable_days,best_before_days,is_active)
values
 ('96000000-0000-4000-8000-000000000012',2026,11,'96000000-0000-4000-8000-000000000010',20,48,15,3,5,7,true),
 ('96000000-0000-4000-8000-000000000011',2099,10,'96000000-0000-4000-8000-000000000010',18,72,14,4,6,8,false);
insert into public.change_history(id,entity_type,entity_id,operation,before_data,after_data,reason,changed_by,changed_at)
values
 ('96000000-0000-4000-8000-000000000020','master','96000000-0000-4000-8000-000000000012','update','{}','{}','手動更新','96000000-0000-4000-8000-000000000001','2026-09-13T00:00:00Z'),
 ('96000000-0000-4000-8000-000000000021','master','96000000-0000-4000-8000-000000000012','update','{}','{}','期限更新（自動）',null,'2026-09-13T01:00:00Z');

create function pg_temp.export(dataset text,filters jsonb) returns jsonb language sql as $$
  select public.csv_export(jsonb_build_object('meta',jsonb_build_object('correlation_id',gen_random_uuid()),
    'input',jsonb_build_object('dataset',dataset,'filters',filters)));
$$;
create temporary table results(name text primary key,data jsonb);
grant all on results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
insert into results values('history',pg_temp.export('history','{"entity_id":"96000000-0000-4000-8000-000000000012"}'));
select is((select data->>'ok' from results where name='history'),'true','history export succeeds');
select is((select (data->'data'->>'row_count')::int from results where name='history'),2,'manual and automatic history both exported');
select alike((select data->'data'->>'csv' from results where name='history'),'%システム（自動更新）%','null actor has explicit system name');
select alike((select data->'data'->>'csv' from results where name='history'),'%CSV96 Admin%','manual actor name is retained');
select alike((select data->'data'->>'csv' from results where name='history'),'%96000000-0000-4000-8000-000000000021%','automatic history ID is present');
select is((pg_temp.export('history','{"entity_id":"96000000-0000-4000-8000-000000000012","from_date":"2026-09-14"}')->'data'->>'row_count')::int,0,'history date filtering still applies');

select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000002',true);
insert into results values('masters',pg_temp.export('masters','{"master_type":"ripening_rule","active":"all","search":"CSV96品種"}'));
select is((select data->>'ok' from results where name='masters'),'true','member can export ripening master without SQL exception');
select is((select (data->'data'->>'row_count')::int from results where name='masters'),2,'variety-name search finds both rules');
select alike((select data->'data'->>'csv' from results where name='masters'),'%"エチレン処理温度","エチレン処理時間","寝かせ温度","寝かせ日数","出荷可能日数","賞味期限日数"%','master header includes all calculation fields');
select alike((select data->'data'->>'csv' from results where name='masters'),'%"11","96000000-0000-4000-8000-000000000010","20","48","15","3","5","7","true"%','master row retains exact calculation inputs');
select alike(split_part((select data->'data'->>'csv' from results where name='masters'),E'\r\n',2),
  '%"10"%','rows include the harvest month without a year column');
select is(cardinality(string_to_array(split_part((select data->'data'->>'csv' from results where name='masters'),E'\r\n',1),',')),12,'master header has twelve columns');
select is(cardinality(string_to_array(split_part((select data->'data'->>'csv' from results where name='masters'),E'\r\n',2),',')),12,'master row matches header column count');
select is((pg_temp.export('masters','{"master_type":"ripening_rule","search":"CSV96-KIWI"}')->'data'->>'row_count')::int,1,'default active filter and variety-code search');
select is((pg_temp.export('masters','{"master_type":"ripening_rule","active":"inactive","search":"10"}')->'data'->>'row_count')::int,1,'inactive and harvest-month filters');
select is((pg_temp.export('masters','{"master_type":"ripening_rule","search":"no-match"}')->'data'->>'row_count')::int,0,'empty result remains valid CSV');
select is(pg_temp.export('history','{}')->'error'->>'code','AUTH_FORBIDDEN','member still cannot export history');
select is(pg_temp.export('masters','{"master_type":"unknown"}')->'error'->>'code','VALIDATION_FAILED','unknown master retains business error');
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000003',true);
select is(pg_temp.export('masters','{"master_type":"ripening_rule"}')->'error'->>'code','AUTH_FORBIDDEN','pending user cannot export new master');
reset role;
select is((select count(*) from public.csv_export_audits where exported_by='96000000-0000-4000-8000-000000000001' and result_code='SUCCESS' and row_count=2),1::bigint,'history audit counts automatic entries');
select * from finish();
rollback;
