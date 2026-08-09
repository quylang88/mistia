begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(5);

create or replace function pg_temp.set_actor(p_user_id uuid)
returns void
language plpgsql
as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
    perform set_config('request.jwt.claim.role', case when p_user_id is null then '' else 'authenticated' end, true);
end;
$$;

insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
    (
        '40000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
        'overview-owner@mistia.test', '', timezone('utc'::text, now()),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        timezone('utc'::text, now()), timezone('utc'::text, now())
    ),
    (
        '40000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
        'overview-member@mistia.test', '', timezone('utc'::text, now()),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        timezone('utc'::text, now()), timezone('utc'::text, now())
    ),
    (
        '40000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
        'overview-outsider@mistia.test', '', timezone('utc'::text, now()),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        timezone('utc'::text, now()), timezone('utc'::text, now())
    )
on conflict (id) do nothing;

insert into public.user_profiles(user_id, display_name)
values
    ('40000000-0000-4000-8000-000000000001', 'Overview owner'),
    ('40000000-0000-4000-8000-000000000002', 'Overview member'),
    ('40000000-0000-4000-8000-000000000003', 'Overview outsider')
on conflict (user_id) do update set display_name = excluded.display_name;

insert into public.families(id, name, owner_user_id)
values (
    '40000000-0000-4000-8000-000000000010',
    'Overview preference test',
    '40000000-0000-4000-8000-000000000001'
);

insert into public.family_memberships(family_id, user_id, role)
values
    (
        '40000000-0000-4000-8000-000000000010',
        '40000000-0000-4000-8000-000000000001',
        'owner'
    ),
    (
        '40000000-0000-4000-8000-000000000010',
        '40000000-0000-4000-8000-000000000002',
        'member'
    );

set local role authenticated;
select pg_temp.set_actor('40000000-0000-4000-8000-000000000002');

select lives_ok(
    $$
    update public.user_profiles
    set overview_section_config = '[{"kind":"budgetFocus","isVisible":true}]'::jsonb,
        overview_section_config_updated_at = '2026-08-09T06:00:00Z'
    where user_id = '40000000-0000-4000-8000-000000000002'
    $$,
    'member can update their own Overview preference'
);

select is(
    (
        select overview_section_config -> 0 ->> 'kind'
        from public.user_profiles
        where user_id = '40000000-0000-4000-8000-000000000002'
    ),
    'budgetFocus',
    'member can read their own Overview preference'
);

select pg_temp.set_actor('40000000-0000-4000-8000-000000000001');

select is(
    (
        select overview_section_config -> 0 ->> 'kind'
        from public.user_profiles
        where user_id = '40000000-0000-4000-8000-000000000002'
    ),
    'budgetFocus',
    'active family member can read the viewed member Overview preference'
);

update public.user_profiles
set overview_section_config = '[]'::jsonb,
    overview_section_config_updated_at = '2026-08-09T07:00:00Z'
where user_id = '40000000-0000-4000-8000-000000000002';

select is(
    (
        select overview_section_config -> 0 ->> 'kind'
        from public.user_profiles
        where user_id = '40000000-0000-4000-8000-000000000002'
    ),
    'budgetFocus',
    'family member cannot overwrite another member Overview preference'
);

select pg_temp.set_actor('40000000-0000-4000-8000-000000000003');

select is(
    (
        select count(*)::integer
        from public.user_profiles
        where user_id = '40000000-0000-4000-8000-000000000002'
    ),
    0,
    'unrelated user cannot read a member Overview preference'
);

reset role;
select * from finish();
rollback;
