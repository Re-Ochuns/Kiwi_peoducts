begin;

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_code text not null unique check (btrim(customer_code) <> ''),
  name text not null check (btrim(name) <> ''),
  nickname text check (nickname is null or btrim(nickname) <> ''),
  postal_code text not null check (btrim(postal_code) <> ''),
  address text not null check (btrim(address) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.shipping_destinations (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  destination_name text not null check (btrim(destination_name) <> ''),
  recipient_name text not null check (btrim(recipient_name) <> ''),
  postal_code text not null check (btrim(postal_code) <> ''),
  address text not null check (btrim(address) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  unique (customer_id, destination_name),
  unique (id, customer_id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique check (btrim(order_number) <> ''),
  customer_id uuid not null references public.customers(id) on delete restrict,
  shipping_destination_id uuid not null,
  ordered_on date not null,
  scheduled_ship_on date not null check (scheduled_ship_on >= ordered_on),
  variety_id uuid not null references public.varieties(id) on delete restrict,
  grade_id uuid not null references public.grades(id) on delete restrict,
  ordered_weight_kg public.weight_kg not null check (ordered_weight_kg > 0),
  allocated_weight_kg public.weight_kg not null default 0
    check (allocated_weight_kg <= ordered_weight_kg),
  shipping_destination_snapshot jsonb not null
    check (jsonb_typeof(shipping_destination_snapshot) = 'object'),
  status text not null default 'draft'
    check (status in ('draft', 'confirmed', 'in_progress', 'partially_shipped', 'shipped', 'cancelled')),
  notes text,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  foreign key (shipping_destination_id, customer_id)
    references public.shipping_destinations(id, customer_id) on delete restrict
);

create table public.ripening_lots (
  id uuid primary key default gen_random_uuid(),
  display_id text not null unique check (btrim(display_id) <> ''),
  variety_id uuid not null references public.varieties(id) on delete restrict,
  grade_id uuid not null references public.grades(id) on delete restrict,
  total_weight_kg public.weight_kg not null check (total_weight_kg > 0),
  allocated_weight_kg public.weight_kg not null default 0
    check (allocated_weight_kg <= total_weight_kg),
  use_type text check (use_type is null or use_type in ('order', 'reserve', 'mixed')),
  storage_location_id uuid not null references public.storage_locations(id) on delete restrict,
  planned_ethylene_at timestamptz not null,
  planned_completion_at timestamptz not null
    check (planned_completion_at >= planned_ethylene_at),
  master_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(master_snapshot) = 'object'),
  status text not null default 'draft'
    check (status in ('draft', 'confirmed', 'in_progress', 'completed', 'cancelled')),
  assigned_worker_id uuid not null references public.workers(id) on delete restrict,
  needs_review boolean not null default false,
  notes text,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.ripening_allocations (
  id uuid primary key default gen_random_uuid(),
  ripening_lot_id uuid not null references public.ripening_lots(id) on delete restrict,
  allocation_type text not null check (allocation_type in ('order', 'reserve')),
  order_id uuid references public.orders(id) on delete restrict,
  allocated_weight_kg public.weight_kg not null check (allocated_weight_kg > 0),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  check (
    (allocation_type = 'order' and order_id is not null)
    or (allocation_type = 'reserve' and order_id is null)
  )
);

create unique index ripening_allocations_order_per_lot_key
  on public.ripening_allocations (ripening_lot_id, order_id)
  where allocation_type = 'order';
create unique index ripening_allocations_reserve_per_lot_key
  on public.ripening_allocations (ripening_lot_id)
  where allocation_type = 'reserve';

create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  ripening_lot_id uuid not null references public.ripening_lots(id) on delete restrict,
  container_id uuid not null references public.containers(id) on delete restrict,
  reserved_weight_kg public.weight_kg not null check (reserved_weight_kg > 0),
  status text not null default 'active'
    check (status in ('active', 'released', 'consumed')),
  released_at timestamptz,
  consumed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  unique (ripening_lot_id, container_id),
  check (
    (status = 'active' and released_at is null and consumed_at is null)
    or (status = 'released' and released_at is not null and consumed_at is null)
    or (status = 'consumed' and released_at is null and consumed_at is not null)
  )
);

create table public.work_tasks (
  id uuid primary key default gen_random_uuid(),
  task_type text not null check (
    task_type in ('sorting', 'label', 'ethylene_injection', 'ethylene_removal_check', 'ripeness_check', 'shipping')
  ),
  receiving_lot_id uuid references public.receiving_lots(id) on delete restrict,
  label_job_id uuid references public.label_jobs(id) on delete restrict,
  ripening_lot_id uuid references public.ripening_lots(id) on delete restrict,
  order_id uuid references public.orders(id) on delete restrict,
  scheduled_at timestamptz not null,
  due_at timestamptz not null check (due_at >= scheduled_at),
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'cancelled')),
  assigned_worker_id uuid references public.workers(id) on delete restrict,
  completed_at timestamptz,
  completed_by uuid references public.workers(id) on delete restrict,
  notes text,
  target_url text not null check (btrim(target_url) <> ''),
  calendar_event_id text,
  calendar_sync_status text not null default 'pending'
    check (calendar_sync_status in ('not_required', 'pending', 'synced', 'failed')),
  calendar_sync_attempts integer not null default 0 check (calendar_sync_attempts >= 0),
  calendar_sync_error text,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  check (num_nonnulls(receiving_lot_id, label_job_id, ripening_lot_id, order_id) = 1),
  check (
    (task_type = 'sorting' and receiving_lot_id is not null)
    or (task_type = 'label' and label_job_id is not null)
    or (task_type in ('ethylene_injection', 'ethylene_removal_check', 'ripeness_check') and ripening_lot_id is not null)
    or (task_type = 'shipping' and order_id is not null)
  ),
  check (
    (status = 'pending' and completed_at is null and completed_by is null)
    or (status = 'completed' and completed_at is not null and completed_by is not null)
    or (status = 'cancelled' and completed_at is null and completed_by is null)
  ),
  check (
    (calendar_sync_status = 'synced' and nullif(btrim(calendar_event_id), '') is not null and calendar_sync_error is null)
    or (calendar_sync_status = 'failed' and nullif(btrim(calendar_sync_error), '') is not null)
    or (calendar_sync_status in ('not_required', 'pending') and calendar_event_id is null)
  )
);

create index shipping_destinations_customer_idx on public.shipping_destinations (customer_id, is_active);
create index orders_status_ship_idx on public.orders (status, scheduled_ship_on);
create index orders_customer_idx on public.orders (customer_id, ordered_on desc);
create index orders_product_idx on public.orders (variety_id, grade_id, status);
create index ripening_lots_status_schedule_idx on public.ripening_lots (status, planned_ethylene_at);
create index ripening_lots_product_idx on public.ripening_lots (variety_id, grade_id, status);
create index ripening_allocations_lot_idx on public.ripening_allocations (ripening_lot_id);
create index ripening_allocations_order_idx on public.ripening_allocations (order_id) where order_id is not null;
create index inventory_reservations_container_active_idx
  on public.inventory_reservations (container_id) where status = 'active';
create index inventory_reservations_lot_idx on public.inventory_reservations (ripening_lot_id, status);
create index work_tasks_status_due_idx on public.work_tasks (status, due_at);
create index work_tasks_worker_due_idx on public.work_tasks (assigned_worker_id, due_at) where status = 'pending';
create unique index work_tasks_calendar_event_key
  on public.work_tasks (calendar_event_id) where calendar_event_id is not null;

create or replace function private.prevent_order_number_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.order_number is distinct from old.order_number then
    raise exception 'order_number cannot be changed' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_ripening_lot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  active_reservation_weight numeric;
  derived_use_type text;
begin
  if tg_op = 'UPDATE' then
    if new.total_weight_kg < new.allocated_weight_kg then
      raise exception 'ripening allocation exceeds lot weight' using errcode = '23514';
    end if;

    if old.status <> 'draft' and row(new.variety_id, new.grade_id, new.total_weight_kg)
      is distinct from row(old.variety_id, old.grade_id, old.total_weight_kg) then
      raise exception 'started ripening lot product and weight cannot be changed' using errcode = '23514';
    end if;

    if new.status is distinct from old.status and not (
      (old.status = 'draft' and new.status in ('confirmed', 'cancelled'))
      or (old.status = 'confirmed' and new.status in ('draft', 'in_progress', 'cancelled'))
      or (old.status = 'in_progress' and new.status = 'completed')
    ) then
      raise exception 'invalid ripening lot status transition' using errcode = '23514';
    end if;
  end if;

  if new.status = 'confirmed' and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    select case
      when bool_or(a.allocation_type = 'order') and bool_or(a.allocation_type = 'reserve') then 'mixed'
      when bool_or(a.allocation_type = 'order') then 'order'
      when bool_or(a.allocation_type = 'reserve') then 'reserve'
      else null
    end
    into derived_use_type
    from public.ripening_allocations a
    where a.ripening_lot_id = new.id;

    select coalesce(sum(r.reserved_weight_kg), 0)
    into active_reservation_weight
    from public.inventory_reservations r
    where r.ripening_lot_id = new.id and r.status = 'active';

    if new.allocated_weight_kg <> new.total_weight_kg or derived_use_type is null then
      raise exception 'ripening allocation total must equal lot weight' using errcode = '23514';
    end if;
    if active_reservation_weight <> new.total_weight_kg then
      raise exception 'active reservation total must equal lot weight' using errcode = '23514';
    end if;
    new.use_type := derived_use_type;
  end if;

  return new;
end;
$$;

create or replace function private.apply_ripening_allocation_delta()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  lot_id uuid;
  lot_status text;
  lot_variety_id uuid;
  lot_grade_id uuid;
  lot_delta numeric := 0;
  order_delta numeric := 0;
  order_row public.orders%rowtype;
begin
  lot_id := case when tg_op = 'DELETE' then old.ripening_lot_id else new.ripening_lot_id end;

  if tg_op = 'UPDATE' and new.ripening_lot_id <> old.ripening_lot_id then
    raise exception 'ripening allocation cannot move between lots' using errcode = '23514';
  end if;

  select status, variety_id, grade_id
  into lot_status, lot_variety_id, lot_grade_id
  from public.ripening_lots
  where id = lot_id
  for update;

  if lot_status <> 'draft' then
    raise exception 'ripening allocations can only change while lot is draft' using errcode = '23514';
  end if;

  lot_delta :=
    (case when tg_op <> 'DELETE' then new.allocated_weight_kg else 0 end)
    - (case when tg_op <> 'INSERT' then old.allocated_weight_kg else 0 end);

  update public.ripening_lots
  set allocated_weight_kg = allocated_weight_kg + lot_delta
  where id = lot_id
    and allocated_weight_kg + lot_delta between 0 and total_weight_kg;

  if not found then
    raise exception 'ripening allocation exceeds lot weight' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.order_id is distinct from old.order_id then
    raise exception 'allocation order cannot be changed' using errcode = '23514';
  end if;

  if tg_op <> 'DELETE' and new.allocation_type = 'order' then
    select * into order_row from public.orders where id = new.order_id for update;
    if not found then
      raise exception 'order not found' using errcode = '23503';
    end if;
    if order_row.status not in ('confirmed', 'in_progress', 'partially_shipped') then
      raise exception 'order is not available for ripening allocation' using errcode = '23514';
    end if;
    if row(order_row.variety_id, order_row.grade_id)
      is distinct from row(lot_variety_id, lot_grade_id) then
      raise exception 'order product does not match ripening lot' using errcode = '23514';
    end if;
  end if;

  if tg_op <> 'INSERT' and old.allocation_type = 'order' then
    order_delta := order_delta - old.allocated_weight_kg;
  end if;
  if tg_op <> 'DELETE' and new.allocation_type = 'order' then
    order_delta := order_delta + new.allocated_weight_kg;
  end if;

  if order_delta <> 0 then
    update public.orders
    set allocated_weight_kg = allocated_weight_kg + order_delta
    where id = coalesce(new.order_id, old.order_id)
      and allocated_weight_kg + order_delta between 0 and ordered_weight_kg;
    if not found then
      raise exception 'order allocation exceeds ordered weight' using errcode = '23514';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.refresh_ripening_lot_use_type()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_lot_id uuid;
  derived_use_type text;
begin
  target_lot_id := case when tg_op = 'DELETE' then old.ripening_lot_id else new.ripening_lot_id end;
  select case
    when bool_or(allocation_type = 'order') and bool_or(allocation_type = 'reserve') then 'mixed'
    when bool_or(allocation_type = 'order') then 'order'
    when bool_or(allocation_type = 'reserve') then 'reserve'
    else null
  end
  into derived_use_type
  from public.ripening_allocations
  where ripening_lot_id = target_lot_id;

  update public.ripening_lots set use_type = derived_use_type where id = target_lot_id;
  return null;
end;
$$;

create or replace function private.apply_inventory_reservation_delta()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  lot_id uuid;
  container_id_value uuid;
  lot_row public.ripening_lots%rowtype;
  container_row public.containers%rowtype;
  reservation_delta numeric := 0;
begin
  lot_id := case when tg_op = 'DELETE' then old.ripening_lot_id else new.ripening_lot_id end;
  container_id_value := case when tg_op = 'DELETE' then old.container_id else new.container_id end;

  if tg_op = 'UPDATE' and row(new.ripening_lot_id, new.container_id)
    is distinct from row(old.ripening_lot_id, old.container_id) then
    raise exception 'inventory reservation cannot move' using errcode = '23514';
  end if;

  select * into lot_row from public.ripening_lots where id = lot_id for update;
  select * into container_row from public.containers where id = container_id_value for update;

  if tg_op = 'INSERT' and lot_row.status <> 'draft' then
    raise exception 'reservation can only be added while lot is draft' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' and lot_row.status <> 'draft' then
    raise exception 'reservation can only be deleted while lot is draft' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if new.reserved_weight_kg is distinct from old.reserved_weight_kg
      and lot_row.status <> 'draft' then
      raise exception 'reservation weight can only be changed while lot is draft' using errcode = '23514';
    end if;
    if old.status = 'active' and new.status = 'released' and lot_row.status <> 'draft' then
      raise exception 'reservation can only be released while lot is draft' using errcode = '23514';
    end if;
    if old.status = 'active' and new.status = 'consumed' and lot_row.status not in ('confirmed', 'in_progress') then
      raise exception 'reservation can only be consumed after confirmation' using errcode = '23514';
    end if;
    if old.status <> new.status and not (old.status = 'active' and new.status in ('released', 'consumed')) then
      raise exception 'invalid reservation status transition' using errcode = '23514';
    end if;
    if old.status <> 'active' and new.reserved_weight_kg is distinct from old.reserved_weight_kg then
      raise exception 'finished reservation weight cannot be changed' using errcode = '23514';
    end if;
  end if;

  if tg_op <> 'DELETE' and new.status = 'active' then
    if container_row.status <> 'cold_storage' then
      raise exception 'only cold-storage inventory can be reserved' using errcode = '23514';
    end if;
    if row(container_row.variety_id, container_row.grade_id)
      is distinct from row(lot_row.variety_id, lot_row.grade_id) then
      raise exception 'container product does not match ripening lot' using errcode = '23514';
    end if;
  end if;

  reservation_delta :=
    (case when tg_op <> 'DELETE' and new.status = 'active' then new.reserved_weight_kg else 0 end)
    - (case when tg_op <> 'INSERT' and old.status = 'active' then old.reserved_weight_kg else 0 end);

  update public.containers
  set reserved_weight_kg = reserved_weight_kg + reservation_delta
  where id = container_id_value
    and reserved_weight_kg + reservation_delta between 0 and current_weight_kg;

  if not found then
    raise exception 'reservation exceeds available container weight' using errcode = '23514';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger orders_number_immutable before update on public.orders
for each row execute function private.prevent_order_number_change();
create trigger ripening_lots_display_id_immutable before update on public.ripening_lots
for each row execute function private.prevent_display_id_change();
create trigger ripening_lots_validate before insert or update on public.ripening_lots
for each row execute function private.validate_ripening_lot();
create trigger ripening_allocations_apply_delta before insert or update or delete on public.ripening_allocations
for each row execute function private.apply_ripening_allocation_delta();
create trigger ripening_allocations_refresh_use_type after insert or update or delete on public.ripening_allocations
for each row execute function private.refresh_ripening_lot_use_type();
create trigger inventory_reservations_apply_delta before insert or update or delete on public.inventory_reservations
for each row execute function private.apply_inventory_reservation_delta();

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'customers', 'shipping_destinations', 'orders', 'ripening_lots',
    'ripening_allocations', 'inventory_reservations', 'work_tasks'
  ] loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_audit_fields()',
      table_name || '_set_updated', table_name
    );
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select on public.%I to authenticated', table_name);
    execute format('grant all on public.%I to service_role', table_name);
    execute format(
      'create policy "active users can read %s" on public.%I for select to authenticated using (private.current_user_is_active())',
      table_name, table_name
    );
  end loop;
end;
$$;

alter table public.change_history
  drop constraint change_history_entity_type_check;
alter table public.change_history
  add constraint change_history_entity_type_check check (
    entity_type in (
      'master', 'receiving_lot', 'sorting_result', 'container', 'label_job',
      'customer', 'shipping_destination', 'order', 'ripening_lot',
      'ripening_allocation', 'inventory_reservation', 'work_task'
    )
  );

comment on table public.customers is 'Customers whose personal information is visible only to active authenticated users.';
comment on table public.shipping_destinations is 'Multiple reusable shipping destinations belonging to one customer.';
comment on table public.orders is 'Customer orders measured in kilograms with a destination snapshot and allocation total.';
comment on table public.ripening_lots is 'Ripening plans separated from physical container workflow state.';
comment on table public.ripening_allocations is 'One-to-many order or reserve breakdown for a ripening lot.';
comment on table public.inventory_reservations is 'Weight reservations against sorted cold-storage containers.';
comment on table public.work_tasks is 'Scheduled worker confirmations and Google Calendar synchronization state.';
comment on function private.apply_ripening_allocation_delta() is
  'Atomically maintains lot and order allocation totals while the ripening lot is draft.';
comment on function private.apply_inventory_reservation_delta() is
  'Atomically maintains container reserved weight and rejects over-reservation.';

commit;
