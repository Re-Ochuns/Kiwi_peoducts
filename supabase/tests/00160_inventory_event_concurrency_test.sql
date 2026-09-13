-- No stock event is committed: the winning transaction is rolled back after
-- checking that the second session cannot concurrently update its balance.
create extension if not exists dblink with schema extensions;
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '96000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 's3-concurrency@example.com', '', now(),
  '{"provider":"google","providers":["google"]}', '{}', now(), now()
);
insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
) values (
  '96100000-0000-0000-0000-000000000001', 'S3-CONCURRENCY',
  'aa000000-0000-0000-0000-000000000001', '2027-05-03',
  'a7000000-0000-0000-0000-000000000001', 48.25, 10, 38.25
);
insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, status
) values (
  '96200000-0000-0000-0000-000000000001', 'S3-CONCURRENCY-1',
  '96100000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 10, 10, 'cold_storage'
);
create function private.test_s3_try_event() returns text
language plpgsql set search_path = '' as $$
begin
  insert into public.inventory_events (
    container_id, event_type, quantity_delta_kg, before_weight_kg, after_weight_kg,
    operation_id, occurred_at, reason, created_by
  ) values (
    '96200000-0000-0000-0000-000000000001', 'adjustment', -3, 10, 7,
    gen_random_uuid(), now(), 'concurrency test', '96000000-0000-0000-0000-000000000001'
  );
  return 'inserted';
exception when others then return sqlstate;
end;
$$;
select extensions.dblink_connect('s3_event',
  'host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres sslmode=disable');
select extensions.dblink_exec('s3_event', 'set lock_timeout = ''300ms''');
begin;
select no_plan();
select is(private.test_s3_try_event(), 'inserted', 'first event obtains container lock');
select is((select result from extensions.dblink('s3_event',
  'select private.test_s3_try_event()') as response(result text)),
  '55P03', 'second session cannot bypass held container lock');
select is((select current_weight_kg::numeric from public.containers
  where id = '96200000-0000-0000-0000-000000000001'), 7::numeric,
  'only one stock decrease is visible');
select is((select count(*) from public.inventory_events
  where container_id = '96200000-0000-0000-0000-000000000001'),
  1::bigint, 'failed concurrent insertion leaves no event');
select * from finish();
rollback;
select extensions.dblink_disconnect('s3_event');
delete from public.containers where id = '96200000-0000-0000-0000-000000000001';
delete from public.sorting_results where id = '96100000-0000-0000-0000-000000000001';
delete from auth.users where id = '96000000-0000-0000-0000-000000000001';
drop function private.test_s3_try_event();
drop extension dblink;
