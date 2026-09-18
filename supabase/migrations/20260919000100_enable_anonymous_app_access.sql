begin;

alter table public.profiles
  drop constraint if exists profiles_auth_provider_check;

alter table public.profiles
  add constraint profiles_auth_provider_check
  check (auth_provider in ('google', 'anonymous'));

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_anonymous_user boolean := coalesce(new.is_anonymous, false);
  profile_email text;
  profile_name text;
  provider_name text;
begin
  if is_anonymous_user then
    provider_name := 'anonymous';
    profile_email := 'anonymous+' || new.id::text || '@local.invalid';
    profile_name := coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      'ゲスト'
    );
  else
    provider_name := coalesce(new.raw_app_meta_data ->> 'provider', 'google');
    if provider_name <> 'google' then
      raise exception 'Unsupported authentication provider: %', provider_name
        using errcode = '22023';
    end if;

    profile_email := new.email;
    profile_name := coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(new.email, '@', 1)
    );
  end if;

  insert into public.profiles (
    id,
    email,
    display_name,
    avatar_url,
    auth_provider,
    access_status,
    access_changed_at
  )
  values (
    new.id,
    profile_email,
    left(profile_name, 100),
    nullif(new.raw_user_meta_data ->> 'avatar_url', ''),
    provider_name,
    case when is_anonymous_user then 'active' else 'pending' end,
    case when is_anonymous_user then now() else null end
  );

  if is_anonymous_user then
    insert into public.user_roles (user_id, role)
    values (new.id, 'member');
  end if;

  return new;
end;
$$;

revoke all on function private.handle_new_auth_user()
  from public, anon, authenticated;

comment on table public.profiles is
  'Google and anonymous application identities with their access state.';
comment on function private.handle_new_auth_user() is
  'Creates pending Google profiles or active member-only anonymous profiles.';

commit;
