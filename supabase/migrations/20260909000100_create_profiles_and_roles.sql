begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  avatar_url text,
  auth_provider text not null default 'google'
    check (auth_provider in ('google')),
  access_status text not null default 'pending'
    check (access_status in ('pending', 'active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  access_changed_at timestamptz,
  access_changed_by uuid references public.profiles(id) on delete set null,
  constraint profiles_email_not_blank check (btrim(email) <> ''),
  constraint profiles_display_name_not_blank check (btrim(display_name) <> '')
);

create unique index profiles_email_lower_key on public.profiles (lower(email));
create index profiles_access_status_idx on public.profiles (access_status);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('member', 'administrator')),
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id) on delete set null,
  primary key (user_id, role)
);

create index user_roles_role_idx on public.user_roles (role);

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;

revoke all on public.profiles from anon, authenticated;
revoke all on public.user_roles from anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.user_roles to authenticated;
grant all on public.profiles to service_role;
grant all on public.user_roles to service_role;

create or replace function private.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and access_status = 'active'
  );
$$;

create or replace function private.current_user_has_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_user_is_active()
    and exists (
      select 1
      from public.user_roles
      where user_id = (select auth.uid())
        and role = required_role
    );
$$;

revoke all on function private.current_user_is_active() from public;
revoke all on function private.current_user_has_role(text) from public;
grant execute on function private.current_user_is_active() to authenticated, service_role;
grant execute on function private.current_user_has_role(text) to authenticated, service_role;

create policy "active users can read their own profile"
on public.profiles
for select
to authenticated
using (
  private.current_user_is_active()
  and id = (select auth.uid())
);

create policy "active administrators can read profiles"
on public.profiles
for select
to authenticated
using (private.current_user_has_role('administrator'));

create policy "active users can read their own roles"
on public.user_roles
for select
to authenticated
using (
  private.current_user_is_active()
  and user_id = (select auth.uid())
);

create policy "active administrators can read roles"
on public.user_roles
for select
to authenticated
using (private.current_user_has_role('administrator'));

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_name text;
  provider_name text;
begin
  provider_name := coalesce(new.raw_app_meta_data ->> 'provider', 'google');

  if provider_name <> 'google' then
    raise exception 'Unsupported authentication provider: %', provider_name
      using errcode = '22023';
  end if;

  profile_name := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    split_part(new.email, '@', 1)
  );

  insert into public.profiles (
    id,
    email,
    display_name,
    avatar_url,
    auth_provider
  )
  values (
    new.id,
    new.email,
    left(profile_name, 100),
    nullif(new.raw_user_meta_data ->> 'avatar_url', ''),
    provider_name
  );

  return new;
end;
$$;

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure private.handle_new_auth_user();

create or replace function private.set_user_access(
  target_user_id uuid,
  new_status text,
  new_roles text[] default array[]::text[],
  actor_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new_status not in ('active', 'disabled') then
    raise exception 'Access status must be active or disabled'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(new_roles) as requested(role)
    where requested.role not in ('member', 'administrator')
  ) then
    raise exception 'Unknown access role'
      using errcode = '22023';
  end if;

  if new_status = 'active' and cardinality(new_roles) = 0 then
    raise exception 'An active user must have at least one role'
      using errcode = '22023';
  end if;

  update public.profiles
  set access_status = new_status,
      access_changed_at = now(),
      access_changed_by = actor_user_id,
      updated_at = now()
  where id = target_user_id;

  if not found then
    raise exception 'Profile not found'
      using errcode = 'P0002';
  end if;

  delete from public.user_roles where user_id = target_user_id;

  if new_status = 'active' then
    insert into public.user_roles (user_id, role, assigned_by)
    select target_user_id, requested.role, actor_user_id
    from (
      select distinct unnest(new_roles) as role
    ) as requested;
  end if;
end;
$$;

revoke all on function private.set_user_access(uuid, text, text[], uuid)
  from public, anon, authenticated;
grant execute on function private.set_user_access(uuid, text, text[], uuid)
  to service_role;

comment on table public.profiles is
  'Google-authenticated identities and their application access state.';
comment on table public.user_roles is
  'Access-control roles. These are independent of worker/admin UI modes.';
comment on function private.set_user_access(uuid, text, text[], uuid) is
  'Privileged access approval/disable operation with actor audit identity.';

commit;
