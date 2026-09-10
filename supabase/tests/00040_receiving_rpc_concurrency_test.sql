-- This test uses a second real database session to exercise the row-lock path.
create extension if not exists dblink with schema extensions;

create temporary table receiving_concurrency_result (
  response jsonb not null
) on commit preserve rows;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '60000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'rpc-concurrency@example.com', '', now(),
  '{"provider":"google","providers":["google"]}',
  '{"full_name":"RPC Concurrency"}', now(), now()
);

select private.set_user_access(
  '60000000-0000-0000-0000-000000000001', 'active', array['member']
);

select extensions.dblink_connect(
  'receiving_concurrent',
  'host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres sslmode=disable application_name=receiving_concurrent_test'
);
select extensions.dblink_exec('receiving_concurrent', 'set role authenticated');
select extensions.dblink_exec(
  'receiving_concurrent',
  $$set request.jwt.claim.sub = '60000000-0000-0000-0000-000000000001'$$
);

begin;

-- Hold the target row while the second session starts a correction based on
-- version 1. Once this transaction commits version 2, the waiting RPC must
-- re-read the locked row and return a stale-version conflict.
select id
from public.receiving_lots
where id = 'aa000000-0000-0000-0000-000000000001'
for update;

select extensions.dblink_send_query(
  'receiving_concurrent',
  $remote$
    select public.receiving_correct(jsonb_build_object(
      'meta', jsonb_build_object(
        'idempotency_key', '69000000-0000-4000-8000-000000000001',
        'correlation_id', '6c000000-0000-4000-8000-000000000001'
      ),
      'input', jsonb_build_object(
        'receiving_lot_id', 'aa000000-0000-0000-0000-000000000001',
        'expected_version', 1,
        'reason', '別セッションからの同時修正',
        'source_type', 'harvest',
        'received_date', '2027-05-01',
        'orchard_id', 'a3000000-0000-0000-0000-000000000001',
        'plot_id', 'a4000000-0000-0000-0000-000000000001',
        'tree_id', 'a5000000-0000-0000-0000-000000000001',
        'origin_name', '同時修正側',
        'variety_id', 'a1000000-0000-0000-0000-000000000001',
        'total_weight_kg', 49.00,
        'container_count', 3,
        'worker_id', 'a7000000-0000-0000-0000-000000000001'
      )
    ))::text
  $remote$
);

-- Do not release the lock until the remote RPC is actually waiting for it.
do $$
declare
  attempts integer := 0;
begin
  loop
    exit when exists (
      select 1 from pg_stat_activity
      where application_name = 'receiving_concurrent_test'
        and wait_event_type = 'Lock'
    );
    attempts := attempts + 1;
    if attempts >= 100 then
      raise exception 'remote receiving_correct did not reach the row lock';
    end if;
    perform pg_sleep(0.05);
  end loop;
end;
$$;

update public.receiving_lots
set version = 2,
    origin_name = '先行更新側'
where id = 'aa000000-0000-0000-0000-000000000001';

commit;

insert into receiving_concurrency_result(response)
select response::jsonb
from extensions.dblink_get_result('receiving_concurrent') as result(response text);

select no_plan();

select is(
  (select response -> 'error' ->> 'code' from receiving_concurrency_result),
  'CONFLICT_STALE',
  'a correction waiting on a row lock detects the committed version change'
);
select is(
  (select response -> 'error' -> 'details' -> 'current' ->> 'version' from receiving_concurrency_result),
  '2',
  'the concurrent conflict reports the newly committed version'
);
select is(
  (select version from public.receiving_lots where id = 'aa000000-0000-0000-0000-000000000001'),
  2::bigint,
  'the losing correction does not overwrite the winning update'
);
select is(
  (select count(*) from public.change_history
   where entity_type = 'receiving_lot'
     and entity_id = 'aa000000-0000-0000-0000-000000000001'
     and operation = 'correct'),
  0::bigint,
  'the losing correction does not append change history'
);

select * from finish();

select extensions.dblink_disconnect('receiving_concurrent');
delete from private.idempotency_records
where idempotency_key = '69000000-0000-4000-8000-000000000001';
update public.receiving_lots
set version = 1,
    origin_name = 'デモ農園 北区画A'
where id = 'aa000000-0000-0000-0000-000000000001';
delete from public.profiles where id = '60000000-0000-0000-0000-000000000001';
delete from auth.users where id = '60000000-0000-0000-0000-000000000001';
drop extension dblink;
