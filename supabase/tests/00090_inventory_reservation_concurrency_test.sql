-- This test uses a second database session to verify that concurrent weight
-- reservations serialize on the source container and cannot overbook it.
create extension if not exists dblink with schema extensions;

create or replace function private.test_try_inventory_reservation(
  reservation_id uuid,
  lot_id uuid,
  source_container_id uuid,
  requested_weight public.weight_kg
)
returns text
language plpgsql
set search_path = ''
as $$
begin
  insert into public.inventory_reservations (
    id, ripening_lot_id, container_id, reserved_weight_kg
  ) values (
    reservation_id, lot_id, source_container_id, requested_weight
  );
  return 'inserted';
exception
  when others then
    return sqlstate || ':' || sqlerrm;
end;
$$;

insert into public.sorting_results (
  id, display_id, receiving_lot_id, sorted_on, sorted_by,
  input_weight_kg, output_weight_kg, loss_weight_kg
)
values (
  '71000000-0000-0000-0000-000000000001', '選果-2027-CONCURRENCY',
  'aa000000-0000-0000-0000-000000000001', '2027-05-03',
  'a7000000-0000-0000-0000-000000000001', 48.25, 10.00, 38.25
);

insert into public.containers (
  id, display_id, sorting_result_id, variety_id, grade_id,
  original_weight_kg, current_weight_kg, status, location_id
)
values (
  '72000000-0000-0000-0000-000000000001', '選果-2027-CONCURRENCY-1',
  '71000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000005', 10.00, 10.00, 'cold_storage',
  'a8000000-0000-0000-0000-000000000001'
);

insert into public.ripening_lots (
  id, display_id, variety_id, grade_id, total_weight_kg, storage_location_id,
  planned_ethylene_at, planned_completion_at, assigned_worker_id
)
values
  (
    '73000000-0000-0000-0000-000000000001', '追熟-2027-CONCURRENCY-1',
    'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
    6.00, 'a8000000-0000-0000-0000-000000000001', '2027-06-10 09:00+09',
    '2027-06-20 09:00+09', 'a7000000-0000-0000-0000-000000000001'
  ),
  (
    '73000000-0000-0000-0000-000000000002', '追熟-2027-CONCURRENCY-2',
    'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000005',
    6.00, 'a8000000-0000-0000-0000-000000000001', '2027-06-11 09:00+09',
    '2027-06-21 09:00+09', 'a7000000-0000-0000-0000-000000000001'
  );

insert into public.ripening_allocations (
  ripening_lot_id, allocation_type, allocated_weight_kg
)
values
  ('73000000-0000-0000-0000-000000000001', 'reserve', 6.00),
  ('73000000-0000-0000-0000-000000000002', 'reserve', 6.00);

select extensions.dblink_connect(
  'reservation_concurrent',
  'host=supabase_db_kiwi_products port=5432 dbname=postgres user=postgres password=postgres sslmode=disable application_name=reservation_concurrent_test'
);

begin;

insert into public.inventory_reservations (
  id, ripening_lot_id, container_id, reserved_weight_kg
)
values (
  '74000000-0000-0000-0000-000000000001',
  '73000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  6.00
);

select extensions.dblink_send_query(
  'reservation_concurrent',
  $remote$
    select private.test_try_inventory_reservation(
      '74000000-0000-0000-0000-000000000002',
      '73000000-0000-0000-0000-000000000002',
      '72000000-0000-0000-0000-000000000001',
      6.00
    )
  $remote$
);

do $$
declare
  attempts integer := 0;
begin
  loop
    exit when exists (
      select 1 from pg_stat_activity
      where application_name = 'reservation_concurrent_test'
        and wait_event_type = 'Lock'
    );
    attempts := attempts + 1;
    if attempts >= 100 then
      raise exception 'remote reservation did not reach the container row lock';
    end if;
    perform pg_sleep(0.05);
  end loop;
end;
$$;

commit;

create temporary table reservation_concurrency_result (
  result text not null
) on commit preserve rows;

insert into reservation_concurrency_result(result)
select result
from extensions.dblink_get_result('reservation_concurrent') as response(result text);

select no_plan();

select is(
  (select result from reservation_concurrency_result),
  '23514:reservation exceeds available container weight',
  'the concurrent reservation waiting on the row lock is rejected'
);
select is(
  (select reserved_weight_kg::numeric from public.containers where id = '72000000-0000-0000-0000-000000000001'),
  6.00::numeric,
  'the source container keeps only the winning reservation weight'
);
select is(
  (select count(*) from public.inventory_reservations where container_id = '72000000-0000-0000-0000-000000000001'),
  1::bigint,
  'the losing concurrent reservation row is rolled back'
);

select * from finish();

select extensions.dblink_disconnect('reservation_concurrent');
delete from public.inventory_reservations
where id = '74000000-0000-0000-0000-000000000001';
delete from public.ripening_allocations
where ripening_lot_id in (
  '73000000-0000-0000-0000-000000000001',
  '73000000-0000-0000-0000-000000000002'
);
delete from public.ripening_lots
where id in (
  '73000000-0000-0000-0000-000000000001',
  '73000000-0000-0000-0000-000000000002'
);
delete from public.containers where id = '72000000-0000-0000-0000-000000000001';
delete from public.sorting_results where id = '71000000-0000-0000-0000-000000000001';
drop function private.test_try_inventory_reservation(uuid, uuid, uuid, public.weight_kg);
drop extension dblink;
