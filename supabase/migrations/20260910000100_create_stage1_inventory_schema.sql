begin;

create domain public.weight_kg as numeric
  check (value >= 0 and value <= 9999999999.99 and value = round(value, 2));

create or replace function private.set_updated_audit_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;

create or replace function private.prevent_display_id_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.display_id is distinct from old.display_id then
    raise exception 'display_id cannot be changed' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.prevent_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'change history is append-only' using errcode = '23514';
end;
$$;

create table public.varieties (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null unique check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.grades (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code in ('5L', '4L', '3L', 'LL', 'L', 'M', 'S', 'SS')),
  display_order smallint not null unique check (display_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.orchards (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.orchard_plots (
  id uuid primary key default gen_random_uuid(),
  orchard_id uuid not null references public.orchards(id) on delete restrict,
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  unique (orchard_id, code)
);

create table public.trees (
  id uuid primary key default gen_random_uuid(),
  plot_id uuid not null references public.orchard_plots(id) on delete restrict,
  variety_id uuid not null references public.varieties(id) on delete restrict,
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  unique (plot_id, code)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  management_code text not null unique check (btrim(management_code) <> ''),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.storage_locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  location_type text not null check (location_type in ('cold_storage', 'other')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.sorting_deadline_rules (
  id uuid primary key default gen_random_uuid(),
  variety_id uuid not null unique references public.varieties(id) on delete restrict,
  deadline_days smallint not null default 30 check (deadline_days > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.receiving_lots (
  id uuid primary key default gen_random_uuid(),
  display_id text not null unique check (btrim(display_id) <> ''),
  source_type text not null check (source_type in ('harvest', 'purchase')),
  received_on date not null,
  orchard_id uuid references public.orchards(id) on delete restrict,
  plot_id uuid references public.orchard_plots(id) on delete restrict,
  tree_id uuid references public.trees(id) on delete restrict,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  supplier_reference text,
  origin_name text not null check (btrim(origin_name) <> ''),
  variety_id uuid not null references public.varieties(id) on delete restrict,
  total_weight_kg public.weight_kg not null check (total_weight_kg > 0),
  container_count integer not null check (container_count > 0),
  sorting_due_on date not null check (sorting_due_on >= received_on),
  status text not null default 'awaiting_sorting'
    check (status in ('awaiting_sorting', 'sorted')),
  received_by uuid not null references public.workers(id) on delete restrict,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  check (
    (source_type = 'harvest' and tree_id is not null and supplier_id is null and supplier_reference is null)
    or
    (source_type = 'purchase' and tree_id is null and supplier_id is not null and nullif(btrim(supplier_reference), '') is not null)
  )
);

create table public.sorting_results (
  id uuid primary key default gen_random_uuid(),
  display_id text not null unique check (btrim(display_id) <> ''),
  receiving_lot_id uuid not null unique references public.receiving_lots(id) on delete restrict,
  sorted_on date not null,
  sorted_by uuid not null references public.workers(id) on delete restrict,
  input_weight_kg public.weight_kg not null check (input_weight_kg > 0),
  output_weight_kg public.weight_kg not null,
  loss_weight_kg public.weight_kg not null,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  check (input_weight_kg = output_weight_kg + loss_weight_kg)
);

create table public.containers (
  id uuid primary key default gen_random_uuid(),
  display_id text not null unique check (btrim(display_id) <> ''),
  sorting_result_id uuid not null references public.sorting_results(id) on delete restrict,
  variety_id uuid not null references public.varieties(id) on delete restrict,
  grade_id uuid not null references public.grades(id) on delete restrict,
  original_weight_kg public.weight_kg not null check (original_weight_kg > 0),
  current_weight_kg public.weight_kg not null check (current_weight_kg <= original_weight_kg),
  reserved_weight_kg public.weight_kg not null default 0 check (reserved_weight_kg <= current_weight_kg),
  status text not null default 'awaiting_label' check (
    status in ('awaiting_label', 'cold_storage', 'ethylene_processing', 'resting', 'awaiting_ripeness_check', 'shippable', 'shipped', 'expired')
  ),
  location_id uuid references public.storage_locations(id) on delete restrict,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict
);

create table public.label_jobs (
  id uuid primary key default gen_random_uuid(),
  container_id uuid not null unique references public.containers(id) on delete restrict,
  status text not null default 'not_printed'
    check (status in ('not_printed', 'partially_printed', 'printed', 'handwritten')),
  required_copies integer not null default 1 check (required_copies > 0),
  printed_copies integer not null default 0 check (printed_copies >= 0),
  reprint_count integer not null default 0 check (reprint_count >= 0),
  completed_at timestamptz,
  completed_by uuid references public.workers(id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete restrict,
  check (
    (status = 'not_printed' and printed_copies = 0 and completed_at is null and completed_by is null)
    or (status = 'partially_printed' and printed_copies > 0 and printed_copies < required_copies and completed_at is null and completed_by is null)
    or (status = 'printed' and printed_copies >= required_copies and completed_at is not null and completed_by is not null)
    or (status = 'handwritten' and completed_at is not null and completed_by is not null)
  )
);

create table public.label_events (
  id uuid primary key default gen_random_uuid(),
  label_job_id uuid not null references public.label_jobs(id) on delete restrict,
  event_type text not null check (event_type in ('print', 'reprint', 'handwritten')),
  copies integer not null check (copies > 0),
  performed_at timestamptz not null default now(),
  performed_by uuid not null references public.workers(id) on delete restrict,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict
);

create table public.change_history (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('master', 'receiving_lot', 'sorting_result', 'container', 'label_job')),
  entity_id uuid not null,
  operation text not null check (operation in ('create', 'update', 'transition', 'correct')),
  before_data jsonb,
  after_data jsonb not null,
  reason text not null check (btrim(reason) <> ''),
  changed_at timestamptz not null default now(),
  changed_by uuid not null references public.profiles(id) on delete restrict,
  correlation_id uuid,
  check (before_data is not null or operation = 'create')
);

create table private.idempotency_records (
  idempotency_key uuid primary key,
  function_name text not null check (btrim(function_name) <> ''),
  request_hash text not null check (btrim(request_hash) <> ''),
  response jsonb not null,
  executed_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  check (expires_at > created_at)
);

create index receiving_lots_status_due_idx on public.receiving_lots (status, sorting_due_on);
create index receiving_lots_variety_idx on public.receiving_lots (variety_id);
create index sorting_results_worker_idx on public.sorting_results (sorted_by);
create index containers_status_location_idx on public.containers (status, location_id);
create index containers_sorting_result_idx on public.containers (sorting_result_id);
create index containers_grade_idx on public.containers (grade_id);
create index label_jobs_status_idx on public.label_jobs (status);
create index label_events_job_performed_idx on public.label_events (label_job_id, performed_at);
create index change_history_entity_idx on public.change_history (entity_type, entity_id, changed_at desc);
create index idempotency_records_expires_idx on private.idempotency_records (expires_at);

create or replace function private.validate_receiving_lot_references()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.plot_id is not null and not exists (
    select 1 from public.orchard_plots p where p.id = new.plot_id and p.orchard_id = new.orchard_id
  ) then
    raise exception 'plot does not belong to orchard' using errcode = '23514';
  end if;
  if new.tree_id is not null and not exists (
    select 1 from public.trees t where t.id = new.tree_id and t.plot_id = new.plot_id and t.variety_id = new.variety_id
  ) then
    raise exception 'tree does not match plot and variety' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_receiving_lot_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  result_row public.sorting_results%rowtype;
  container_total numeric;
begin
  if new.status is distinct from old.status then
    if not (old.status = 'awaiting_sorting' and new.status = 'sorted') then
      raise exception 'invalid receiving lot status transition' using errcode = '23514';
    end if;
    select * into result_row from public.sorting_results where receiving_lot_id = new.id;
    if not found then
      raise exception 'sorting result is required' using errcode = '23514';
    end if;
    select coalesce(sum(original_weight_kg), 0) into container_total
      from public.containers where sorting_result_id = result_row.id;
    if result_row.input_weight_kg <> old.total_weight_kg
      or result_row.output_weight_kg <> container_total
      or result_row.loss_weight_kg <> old.total_weight_kg - container_total then
      raise exception 'sorting weights are inconsistent' using errcode = '23514';
    end if;
  end if;
  if old.status = 'sorted' and row(new.source_type, new.received_on, new.tree_id, new.supplier_id, new.variety_id, new.total_weight_kg, new.container_count)
    is distinct from row(old.source_type, old.received_on, old.tree_id, old.supplier_id, old.variety_id, old.total_weight_kg, old.container_count) then
    raise exception 'sorted receiving lot cannot be corrected' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.validate_container_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'awaiting_label' and new.status = 'cold_storage') or
      (old.status = 'cold_storage' and new.status = 'ethylene_processing') or
      (old.status = 'ethylene_processing' and new.status = 'resting') or
      (old.status = 'resting' and new.status = 'awaiting_ripeness_check') or
      (old.status = 'awaiting_ripeness_check' and new.status = 'shippable') or
      (old.status = 'shippable' and new.status in ('shipped', 'expired'))
    ) then
      raise exception 'invalid container status transition' using errcode = '23514';
    end if;
    if new.status = 'cold_storage' and not exists (
      select 1 from public.label_jobs l
      where l.container_id = new.id and l.status in ('printed', 'handwritten')
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

create or replace function private.validate_label_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status and not (
    (old.status = 'not_printed' and new.status in ('partially_printed', 'printed', 'handwritten')) or
    (old.status = 'partially_printed' and new.status in ('printed', 'handwritten'))
  ) then
    raise exception 'invalid label status transition' using errcode = '23514';
  end if;
  if new.printed_copies < old.printed_copies or new.reprint_count < old.reprint_count then
    raise exception 'label counters cannot decrease' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger receiving_lots_validate_references before insert or update on public.receiving_lots
for each row execute function private.validate_receiving_lot_references();
create trigger receiving_lots_validate_transition before update on public.receiving_lots
for each row execute function private.validate_receiving_lot_transition();
create trigger containers_validate_transition before update on public.containers
for each row execute function private.validate_container_transition();
create trigger label_jobs_validate_transition before update on public.label_jobs
for each row execute function private.validate_label_transition();

create trigger receiving_lots_display_id_immutable before update on public.receiving_lots
for each row execute function private.prevent_display_id_change();
create trigger sorting_results_display_id_immutable before update on public.sorting_results
for each row execute function private.prevent_display_id_change();
create trigger containers_display_id_immutable before update on public.containers
for each row execute function private.prevent_display_id_change();

create trigger change_history_append_only before update or delete on public.change_history
for each row execute function private.prevent_history_mutation();

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'varieties','grades','orchards','orchard_plots','trees','suppliers','workers','storage_locations',
    'sorting_deadline_rules','receiving_lots','sorting_results','containers','label_jobs'
  ] loop
    execute format('create trigger %I before update on public.%I for each row execute function private.set_updated_audit_fields()', table_name || '_set_updated', table_name);
  end loop;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'varieties','grades','orchards','orchard_plots','trees','suppliers','workers','storage_locations',
    'sorting_deadline_rules','receiving_lots','sorting_results','containers','label_jobs','label_events'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select on public.%I to authenticated', table_name);
    execute format('grant all on public.%I to service_role', table_name);
    execute format('create policy "active users can read %s" on public.%I for select to authenticated using (private.current_user_is_active())', table_name, table_name);
  end loop;
end;
$$;

alter table public.change_history enable row level security;
revoke all on public.change_history from anon, authenticated;
grant select on public.change_history to authenticated;
grant all on public.change_history to service_role;
create policy "active administrators can read change history"
on public.change_history for select to authenticated
using (private.current_user_has_role('administrator'));

revoke all on private.idempotency_records from public, anon, authenticated;
grant all on private.idempotency_records to service_role;

create or replace function private.delete_expired_idempotency_records()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare deleted_count bigint;
begin
  delete from private.idempotency_records where expires_at <= now();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;
revoke all on function private.delete_expired_idempotency_records() from public, anon, authenticated;
grant execute on function private.delete_expired_idempotency_records() to service_role;

comment on domain public.weight_kg is 'Non-negative kilogram quantity with 0.01 kg precision.';
comment on table public.receiving_lots is 'Stage 1 harvest and purchase lots before whole-lot sorting.';
comment on table public.sorting_results is 'One confirmed whole-lot sorting result per receiving lot.';
comment on table public.containers is 'Individually labeled inventory quantities produced by sorting.';
comment on table public.change_history is 'Application-written immutable before/after audit records.';
comment on table private.idempotency_records is 'RPC responses retained for at least 24 hours for safe replay.';

commit;
