begin;

select plan(16);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'user_roles', 'user_roles table exists');
select has_function(
  'private',
  'current_user_is_active',
  array[]::text[],
  'active-user helper exists'
);
select has_function(
  'private',
  'current_user_has_role',
  array['text'],
  'role helper exists'
);

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
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'pending@example.com',
    '',
    now(),
    '{"provider":"google","providers":["google"]}'::jsonb,
    '{"full_name":"Pending User"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'member@example.com',
    '',
    now(),
    '{"provider":"google","providers":["google"]}'::jsonb,
    '{"full_name":"Member User"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'admin@example.com',
    '',
    now(),
    '{"provider":"google","providers":["google"]}'::jsonb,
    '{"full_name":"Admin User"}'::jsonb,
    now(),
    now()
  );

select is(
  (select count(*) from public.profiles),
  3::bigint,
  'Google auth users receive profiles'
);

select is(
  (select count(*) from public.profiles where access_status = 'pending'),
  3::bigint,
  'new profiles start pending'
);

select private.set_user_access(
  '10000000-0000-0000-0000-000000000002',
  'active',
  array['member']
);
select private.set_user_access(
  '10000000-0000-0000-0000-000000000003',
  'active',
  array['administrator']
);

set local role anon;
select throws_ok(
  $$select * from public.profiles$$,
  '42501',
  null,
  'anonymous users cannot select profiles'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*) from public.profiles),
  0::bigint,
  'pending users cannot read profiles'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select ok(private.current_user_is_active(), 'approved member is active');
select isnt(
  private.current_user_has_role('administrator'),
  true,
  'member is not an administrator'
);
select is(
  (select count(*) from public.profiles),
  1::bigint,
  'member reads only own profile'
);
select is(
  (select count(*) from public.user_roles),
  1::bigint,
  'member reads only own role'
);
select throws_ok(
  $$update public.profiles set display_name = 'Changed' where id = '10000000-0000-0000-0000-000000000002'$$,
  '42501',
  null,
  'authenticated users cannot update profiles directly'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select ok(
  private.current_user_has_role('administrator'),
  'approved administrator is detected'
);
select is(
  (select count(*) from public.profiles),
  3::bigint,
  'administrator reads all profiles'
);
select is(
  (select count(*) from public.user_roles),
  2::bigint,
  'administrator reads all roles'
);
reset role;

select private.set_user_access(
  '10000000-0000-0000-0000-000000000002',
  'disabled',
  array[]::text[],
  '10000000-0000-0000-0000-000000000003'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select isnt(private.current_user_is_active(), true, 'disabled user is not active');
select is(
  (select count(*) from public.profiles),
  0::bigint,
  'disabled user cannot read profiles'
);
reset role;

select * from finish();
rollback;
