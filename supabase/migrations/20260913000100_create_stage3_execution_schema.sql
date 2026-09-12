begin;

-- A ripening output has its own stable container ID. Its source containers are
-- traceable through the lot's inventory_reservations; no finalized sorting is
-- rewritten when a source container is split for ripening.
alter table public.ripening_lots add constraint ripening_lots_product_key
  unique (id, variety_id, grade_id);
alter table public.containers alter column sorting_result_id drop not null;
alter table public.containers
  add column ripening_lot_id uuid,
  add column shippable_until timestamptz,
  add column best_before_at timestamptz,
  add column expired_at timestamptz,
  add column needs_review boolean not null default false,
  add constraint containers_origin_check
    check (num_nonnulls(sorting_result_id, ripening_lot_id) = 1),
  add constraint containers_ripening_product_fk
    foreign key (ripening_lot_id, variety_id, grade_id)
    references public.ripening_lots(id, variety_id, grade_id) on delete restrict,
  add constraint containers_deadlines_check check (
    (shippable_until is null and best_before_at is null and expired_at is null)
    or (shippable_until is not null and best_before_at is not null
        and shippable_until <= best_before_at
        and (expired_at is null or expired_at >= best_before_at))
  ),
  add constraint containers_shipped_empty_check
    check (status <> 'shipped' or current_weight_kg = 0);

create index containers_ripening_lot_idx on public.containers(ripening_lot_id)
  where ripening_lot_id is not null;
create index containers_deadline_idx on public.containers(best_before_at)
  where best_before_at is not null and status <> 'expired';

create table public.ripening_work_results (
  id uuid primary key default gen_random_uuid(),
  ripening_lot_id uuid not null references public.ripening_lots(id) on delete restrict,
  work_type text not null check (
    work_type in ('ethylene_injection', 'ethylene_removal_check', 'ripeness_check')),
  actual_at timestamptz not null,
  actual_temperature numeric not null check (
    actual_temperature > '-Infinity'::numeric and actual_temperature < 'Infinity'::numeric),
  location_id uuid not null references public.storage_locations(id) on delete restrict,
  performed_by uuid not null references public.workers(id) on delete restrict,
  checked boolean not null check (checked),
  -- Removal and start of resting belong to one recorded operation.
  rest_started_at timestamptz,
  rest_temperature numeric check (
    rest_temperature > '-Infinity'::numeric and rest_temperature < 'Infinity'::numeric),
  notes text,
  operation_id uuid not null unique,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  unique (ripening_lot_id, work_type),
  check (
    (work_type = 'ethylene_removal_check' and rest_started_at is not null
      and rest_temperature is not null and rest_started_at >= actual_at)
    or (work_type <> 'ethylene_removal_check'
      and rest_started_at is null and rest_temperature is null))
);

create table public.shipments (
  id uuid primary key default gen_random_uuid(),
  display_id text not null unique check (btrim(display_id) <> ''),
  order_id uuid not null references public.orders(id) on delete restrict,
  shipped_at timestamptz not null,
  shipped_by uuid not null references public.workers(id) on delete restrict,
  customer_snapshot jsonb not null check (
    jsonb_typeof(customer_snapshot) = 'object' and customer_snapshot <> '{}'::jsonb),
  shipping_destination_snapshot jsonb not null check (
    jsonb_typeof(shipping_destination_snapshot) = 'object'
    and shipping_destination_snapshot <> '{}'::jsonb),
  status text not null default 'confirmed' check (status in ('confirmed', 'cancelled')),
  operation_id uuid not null unique,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id) on delete restrict,
  cancellation_reason text,
  cancellation_operation_id uuid unique,
  notes text,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  check (
    (status = 'confirmed' and cancelled_at is null and cancelled_by is null
      and cancellation_reason is null and cancellation_operation_id is null)
    or (status = 'cancelled' and cancelled_at is not null and cancelled_at >= shipped_at
      and cancelled_by is not null and nullif(btrim(cancellation_reason), '') is not null
      and cancellation_operation_id is not null))
);
create index shipments_order_idx on public.shipments(order_id, shipped_at);
create index shipments_status_idx on public.shipments(status, shipped_at);

create table public.shipment_lines (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  container_id uuid not null references public.containers(id) on delete restrict,
  shipped_weight_kg public.weight_kg not null check (shipped_weight_kg > 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  unique (shipment_id, container_id)
);
create index shipment_lines_container_idx on public.shipment_lines(container_id);

create table public.inventory_events (
  id uuid primary key default gen_random_uuid(),
  container_id uuid not null references public.containers(id) on delete restrict,
  event_type text not null check (
    event_type in ('ripening_out', 'ripening_in', 'shipment', 'shipment_cancel', 'adjustment')),
  quantity_delta_kg numeric not null check (
    quantity_delta_kg <> 0 and abs(quantity_delta_kg) <= 9999999999.99
    and quantity_delta_kg = round(quantity_delta_kg, 2)),
  before_weight_kg public.weight_kg not null,
  after_weight_kg public.weight_kg not null,
  ripening_lot_id uuid references public.ripening_lots(id) on delete restrict,
  shipment_line_id uuid references public.shipment_lines(id) on delete restrict,
  reverses_event_id uuid unique references public.inventory_events(id) on delete restrict,
  operation_id uuid not null,
  occurred_at timestamptz not null,
  reason text not null check (btrim(reason) <> ''),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  unique (operation_id, container_id, event_type),
  check (after_weight_kg = before_weight_kg + quantity_delta_kg),
  check (
    (event_type = 'ripening_out' and quantity_delta_kg < 0
      and ripening_lot_id is not null and shipment_line_id is null and reverses_event_id is null)
    or (event_type = 'ripening_in' and quantity_delta_kg > 0
      and ripening_lot_id is not null and shipment_line_id is null and reverses_event_id is null)
    or (event_type = 'shipment' and quantity_delta_kg < 0
      and shipment_line_id is not null and ripening_lot_id is null and reverses_event_id is null)
    or (event_type = 'shipment_cancel' and quantity_delta_kg > 0
      and shipment_line_id is not null and ripening_lot_id is null and reverses_event_id is not null)
    or (event_type = 'adjustment' and ripening_lot_id is null
      and shipment_line_id is null and reverses_event_id is null))
);
create index inventory_events_container_idx on public.inventory_events(container_id, created_at, id);
create index inventory_events_ripening_idx on public.inventory_events(ripening_lot_id)
  where ripening_lot_id is not null;
create unique index inventory_events_shipment_line_type_key
  on public.inventory_events(shipment_line_id, event_type) where shipment_line_id is not null;

create function private.guard_s3_container_origin()
returns trigger language plpgsql set search_path = '' as $$
begin
  if row(new.sorting_result_id, new.ripening_lot_id) is distinct from
      row(old.sorting_result_id, old.ripening_lot_id) then
    raise exception 'container origin cannot be changed' using errcode = '23514';
  end if;
  if old.ripening_lot_id is not null and
      row(new.variety_id, new.grade_id, new.original_weight_kg) is distinct from
      row(old.variety_id, old.grade_id, old.original_weight_kg) then
    raise exception 'ripening container identity cannot be changed' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger containers_s3_origin before update on public.containers
  for each row execute function private.guard_s3_container_origin();

-- Same normal forward transitions as S1, plus reversal of an emptied shipment.
-- Client writes remain denied; the shipment event trigger drives cancellation.
create or replace function private.validate_container_transition()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'awaiting_label' and new.status = 'cold_storage') or
      (old.status = 'cold_storage' and new.status = 'ethylene_processing') or
      (old.status = 'ethylene_processing' and new.status = 'resting') or
      (old.status = 'resting' and new.status = 'awaiting_ripeness_check') or
      (old.status = 'awaiting_ripeness_check' and new.status = 'shippable') or
      (old.status = 'shippable' and new.status in ('shipped', 'expired')) or
      (old.status = 'shipped' and new.status in ('shippable', 'expired') and new.current_weight_kg > 0)
    ) then
      raise exception 'invalid container status transition' using errcode = '23514';
    end if;
    if new.status = 'cold_storage' and not exists (
      select 1 from public.label_jobs l where l.container_id = new.id
      and l.status in ('printed', 'handwritten')
    ) then
      raise exception 'label completion is required' using errcode = '23514';
    end if;
    if new.status = 'shipped' and new.current_weight_kg <> 0 then
      raise exception 'shipped container must be empty' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create function private.apply_inventory_event()
returns trigger language plpgsql set search_path = '' as $$
declare
  c public.containers%rowtype;
  original public.inventory_events%rowtype;
  line public.shipment_lines%rowtype;
  shipment public.shipments%rowtype;
  target_order public.orders%rowtype;
begin
  if new.shipment_line_id is not null then
    select * into strict line from public.shipment_lines where id = new.shipment_line_id;
    select * into strict shipment from public.shipments where id = line.shipment_id for update;
    select * into strict target_order from public.orders where id = shipment.order_id for no key update;
  end if;
  select * into strict c from public.containers where id = new.container_id for no key update;
  if c.current_weight_kg <> new.before_weight_kg then
    raise exception 'inventory event balance is stale' using errcode = '23514';
  end if;
  if new.after_weight_kg < c.reserved_weight_kg or new.after_weight_kg > c.original_weight_kg then
    raise exception 'inventory event exceeds available weight or capacity' using errcode = '23514';
  end if;
  if new.event_type in ('shipment', 'shipment_cancel') then
    if line.container_id <> c.id or line.shipped_weight_kg <> abs(new.quantity_delta_kg) then
      raise exception 'shipment event does not match line' using errcode = '23514';
    end if;
    if c.ripening_lot_id is null or
        row(c.variety_id, c.grade_id) is distinct from row(target_order.variety_id, target_order.grade_id) then
      raise exception 'shipment container product does not match order' using errcode = '23514';
    end if;
  end if;
  if new.event_type = 'shipment' then
    if shipment.status <> 'confirmed' or target_order.status in ('draft', 'cancelled')
        or c.status <> 'shippable' or c.best_before_at is null or c.shippable_until is null
        or least(c.best_before_at, c.shippable_until) <= greatest(statement_timestamp(), shipment.shipped_at) then
      raise exception 'container is not available for shipment' using errcode = '23514';
    end if;
    if (select coalesce(sum(l.shipped_weight_kg), 0)
        from public.shipment_lines l join public.shipments s on s.id = l.shipment_id
        where s.order_id = shipment.order_id and s.status = 'confirmed') > target_order.ordered_weight_kg then
      raise exception 'shipment exceeds ordered weight' using errcode = '23514';
    end if;
  elsif new.event_type = 'shipment_cancel' then
    select * into strict original from public.inventory_events where id = new.reverses_event_id;
    if shipment.status <> 'cancelled' or original.event_type <> 'shipment'
        or original.container_id <> c.id or original.shipment_line_id <> new.shipment_line_id
        or original.quantity_delta_kg <> -new.quantity_delta_kg
        or new.occurred_at < original.occurred_at then
      raise exception 'invalid shipment reversal' using errcode = '23514';
    end if;
  elsif new.event_type = 'ripening_in' then
    if c.ripening_lot_id is distinct from new.ripening_lot_id then
      raise exception 'ripening input does not match output container' using errcode = '23514';
    end if;
  elsif new.event_type = 'ripening_out' then
    if not exists (select 1 from public.inventory_reservations r
      where r.container_id = c.id and r.ripening_lot_id = new.ripening_lot_id
      and r.status = 'consumed' and r.reserved_weight_kg = -new.quantity_delta_kg) then
      raise exception 'ripening output requires consumed reservation' using errcode = '23514';
    end if;
  end if;
  update public.containers set
    current_weight_kg = new.after_weight_kg,
    version = version + 1,
    status = case
      when new.event_type = 'shipment' and new.after_weight_kg = 0 then 'shipped'
      when new.event_type = 'shipment_cancel' and c.status = 'shipped' then
        case when c.best_before_at <= statement_timestamp() then 'expired' else 'shippable' end
      else status end,
    expired_at = case when new.event_type = 'shipment_cancel' and c.status = 'shipped'
      and c.best_before_at <= statement_timestamp() then statement_timestamp() else expired_at end
  where id = c.id;
  insert into public.change_history (
    entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
  ) select 'container', c.id, 'update', to_jsonb(c), to_jsonb(updated),
    new.reason, new.created_by, new.operation_id
    from public.containers updated where updated.id = c.id;
  return new;
end;
$$;
create trigger inventory_events_apply before insert on public.inventory_events
  for each row execute function private.apply_inventory_event();
create trigger inventory_events_append_only before update or delete on public.inventory_events
  for each row execute function private.prevent_history_mutation();
create trigger shipment_lines_append_only before update or delete on public.shipment_lines
  for each row execute function private.prevent_history_mutation();

create function private.guard_shipment()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'shipment cannot be deleted; record a reversal' using errcode = '23514';
  end if;
  if row(new.id, new.display_id, new.order_id, new.shipped_at, new.shipped_by,
      new.customer_snapshot, new.shipping_destination_snapshot, new.operation_id, new.created_by)
    is distinct from row(old.id, old.display_id, old.order_id, old.shipped_at, old.shipped_by,
      old.customer_snapshot, old.shipping_destination_snapshot, old.operation_id, old.created_by)
    or old.status = 'cancelled' then
    raise exception 'shipment facts are immutable' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger shipments_guard before update or delete on public.shipments
  for each row execute function private.guard_shipment();

-- The future shipment RPC must insert header, lines and events in one
-- transaction, including one inverse event per line on cancellation.
create function private.check_shipment_events()
returns trigger language plpgsql set search_path = '' as $$
declare
  shipment_id_value uuid;
  shipment_status text;
begin
  shipment_id_value := case when tg_table_name = 'shipments' then new.id else (to_jsonb(new)->>'shipment_id')::uuid end;
  select status into shipment_status from public.shipments where id = shipment_id_value;
  if not exists (select 1 from public.shipment_lines where shipment_id = shipment_id_value) then
    raise exception 'shipment must contain lines' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.shipment_lines l
    where l.shipment_id = shipment_id_value and (
      not exists (select 1 from public.inventory_events e
        where e.shipment_line_id = l.id and e.event_type = 'shipment')
      or (shipment_status = 'cancelled' and not exists (
        select 1 from public.inventory_events e
        where e.shipment_line_id = l.id and e.event_type = 'shipment_cancel'))
    )
  ) then
    raise exception 'shipment requires matching inventory events' using errcode = '23514';
  end if;
  return null;
end;
$$;
create constraint trigger shipments_events_consistent after insert or update on public.shipments
  deferrable initially deferred for each row execute function private.check_shipment_events();
create constraint trigger shipment_lines_events_consistent after insert on public.shipment_lines
  deferrable initially deferred for each row execute function private.check_shipment_events();

alter table public.change_history drop constraint change_history_entity_type_check;
alter table public.change_history add constraint change_history_entity_type_check check (
  entity_type in ('master', 'receiving_lot', 'sorting_result', 'container', 'label_job',
    'customer', 'shipping_destination', 'order', 'ripening_lot', 'ripening_allocation',
    'inventory_reservation', 'work_task', 'ripening_work_result', 'shipment', 'shipment_line', 'inventory_event')
);

do $$
declare table_name text;
begin
  foreach table_name in array array['ripening_work_results', 'shipments', 'shipment_lines', 'inventory_events'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from public, anon, authenticated', table_name);
    execute format('grant select on public.%I to authenticated', table_name);
    execute format('grant all on public.%I to service_role', table_name);
    execute format('create policy "active users can read %s" on public.%I for select to authenticated using (private.current_user_is_active())', table_name, table_name);
  end loop;
  foreach table_name in array array['ripening_work_results', 'shipments'] loop
    execute format('create trigger %I before update on public.%I for each row execute function private.set_updated_audit_fields()', table_name || '_set_updated', table_name);
  end loop;
end;
$$;
revoke all on function private.guard_s3_container_origin(), private.apply_inventory_event(),
  private.guard_shipment(), private.check_shipment_events() from public, anon, authenticated;

create unique index inventory_events_ripening_once_key
  on public.inventory_events(ripening_lot_id, container_id, event_type)
  where ripening_lot_id is not null;

create function private.guard_ripening_result()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'ripening result cannot be deleted' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if row(new.id, new.ripening_lot_id, new.work_type, new.operation_id, new.created_by)
      is distinct from row(old.id, old.ripening_lot_id, old.work_type, old.operation_id, old.created_by) then
      raise exception 'ripening result identity is immutable' using errcode = '23514';
    end if;
    if nullif(btrim(new.notes), '') is null then
      raise exception 'ripening correction requires a reason in notes' using errcode = '23514';
    end if;
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;
create trigger ripening_work_results_guard before update or delete on public.ripening_work_results
  for each row execute function private.guard_ripening_result();

create function private.record_s3_history()
returns trigger language plpgsql set search_path = '' as $$
declare
  entity_name text;
  data jsonb := to_jsonb(new);
  prior jsonb;
begin
  entity_name := case tg_table_name
    when 'ripening_work_results' then 'ripening_work_result'
    when 'shipments' then 'shipment'
    when 'shipment_lines' then 'shipment_line'
    else 'inventory_event' end;
  if tg_op = 'UPDATE' then prior := to_jsonb(old); end if;
  insert into public.change_history (
    entity_type, entity_id, operation, before_data, after_data, reason, changed_by, correlation_id
  ) values (
    entity_name, new.id, case when tg_op = 'INSERT' then 'create' else 'update' end,
    prior, data,
    coalesce(nullif(data->>'cancellation_reason', ''), nullif(data->>'reason', ''),
      nullif(data->>'notes', ''), entity_name || ' ' || lower(tg_op)),
    coalesce(auth.uid(), (data->>'updated_by')::uuid, new.created_by),
    (data->>'operation_id')::uuid
  );
  return null;
end;
$$;
do $$
declare table_name text;
begin
  foreach table_name in array array['ripening_work_results', 'shipments', 'shipment_lines', 'inventory_events'] loop
    execute format('create trigger %I after insert or update on public.%I for each row execute function private.record_s3_history()', table_name || '_history', table_name);
  end loop;
end;
$$;
revoke all on function private.guard_ripening_result(), private.record_s3_history()
  from public, anon, authenticated;
create function private.validate_s3_ripening_result()
returns trigger language plpgsql set search_path = '' as $$
declare injection_at timestamptz; resting_at timestamptz; later_at timestamptz;
begin
  perform 1 from public.ripening_lots where id = new.ripening_lot_id for no key update;
  select actual_at into injection_at from public.ripening_work_results
    where ripening_lot_id = new.ripening_lot_id and work_type = 'ethylene_injection';
  select rest_started_at into resting_at from public.ripening_work_results
    where ripening_lot_id = new.ripening_lot_id and work_type = 'ethylene_removal_check';
  if new.work_type = 'ethylene_removal_check' and (injection_at is null or new.actual_at < injection_at) then
    raise exception 'removal requires earlier injection' using errcode = '23514';
  end if;
  if new.work_type = 'ripeness_check' and (resting_at is null or new.actual_at < resting_at) then
    raise exception 'ripeness check requires earlier resting start' using errcode = '23514';
  end if;
  if new.work_type = 'ethylene_injection' then
    select actual_at into later_at from public.ripening_work_results
      where ripening_lot_id = new.ripening_lot_id and work_type = 'ethylene_removal_check';
    if later_at < new.actual_at then
      raise exception 'injection cannot follow removal' using errcode = '23514';
    end if;
  elsif new.work_type = 'ethylene_removal_check' then
    select actual_at into later_at from public.ripening_work_results
      where ripening_lot_id = new.ripening_lot_id and work_type = 'ripeness_check';
    if later_at < new.rest_started_at then
      raise exception 'resting cannot follow ripeness check' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger ripening_work_results_validate before insert or update on public.ripening_work_results
  for each row execute function private.validate_s3_ripening_result();

create function private.validate_ripening_container_capacity()
returns trigger language plpgsql set search_path = '' as $$
declare total numeric;
begin
  if new.ripening_lot_id is not null then
    select total_weight_kg into strict total from public.ripening_lots
      where id = new.ripening_lot_id for no key update;
    if (select coalesce(sum(original_weight_kg), 0) from public.containers
        where ripening_lot_id = new.ripening_lot_id) + new.original_weight_kg > total then
      raise exception 'ripening containers exceed planned weight' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger containers_ripening_capacity before insert on public.containers
  for each row execute function private.validate_ripening_container_capacity();
revoke all on function private.validate_s3_ripening_result(),
  private.validate_ripening_container_capacity() from public, anon, authenticated;
comment on table public.ripening_work_results is 'S3 actual measurements, separate from ripening_lots planned values; one record per manual stage.';
comment on table public.inventory_events is 'Append-only signed weight ledger. Insertion locks and updates the container balance atomically.';
comment on column public.containers.shippable_until is 'Exclusive shipping cutoff copied/calculated by the ripening RPC, separate from best-before.';
comment on column public.containers.best_before_at is 'Exclusive best-before cutoff based on actual ethylene injection, not planned completion.';
commit;



