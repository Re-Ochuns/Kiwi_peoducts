begin;

select plan(7);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_anonymous,
  created_at,
  updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '19000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  null,
  '',
  now(),
  '{}'::jsonb,
  '{"display_name":"ゲスト"}'::jsonb,
  true,
  now(),
  now()
);

select is(
  (select auth_provider from public.profiles where id = '19000000-0000-4000-8000-000000000001'),
  'anonymous',
  'anonymous auth user receives an anonymous profile'
);
select is(
  (select access_status from public.profiles where id = '19000000-0000-4000-8000-000000000001'),
  'active',
  'anonymous profile is active immediately'
);
select ok(
  (select email like 'anonymous+%@local.invalid' from public.profiles where id = '19000000-0000-4000-8000-000000000001'),
  'anonymous profile receives a non-personal unique email placeholder'
);
select is(
  (select count(*) from public.user_roles where user_id = '19000000-0000-4000-8000-000000000001' and role = 'member'),
  1::bigint,
  'anonymous profile receives the member role'
);
select is(
  (select count(*) from public.user_roles where user_id = '19000000-0000-4000-8000-000000000001' and role = 'administrator'),
  0::bigint,
  'anonymous profile does not receive administrator access'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
select ok(private.current_user_is_active(), 'anonymous member passes active-user RLS');
select is(
  (select count(*) from public.profiles),
  1::bigint,
  'anonymous member can read only its own profile'
);
reset role;

select * from finish();
rollback;
