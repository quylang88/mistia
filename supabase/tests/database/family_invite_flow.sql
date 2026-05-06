begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select no_plan();

create temp table mistia_test_users (
    label text primary key,
    id uuid not null
);

create temp table mistia_test_families (
    label text primary key,
    id uuid not null
);

create temp table mistia_test_invites (
    label text primary key,
    id uuid not null,
    token text not null
);

create or replace function pg_temp.set_actor(p_user_id uuid)
returns void
language plpgsql
as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_user_id::text, ''), true);
    perform set_config('request.jwt.claim.role', case when p_user_id is null then '' else 'authenticated' end, true);
end;
$$;

create or replace function pg_temp.raises_like(p_sql text, p_pattern text)
returns boolean
language plpgsql
as $$
begin
    execute p_sql;
    return false;
exception
    when others then
        return sqlerrm ilike p_pattern;
end;
$$;

create or replace function pg_temp.user_id(p_label text)
returns uuid
language sql
stable
as $$
    select id from pg_temp.mistia_test_users where label = p_label
$$;

create or replace function pg_temp.family_id(p_label text)
returns uuid
language sql
stable
as $$
    select id from pg_temp.mistia_test_families where label = p_label
$$;

create or replace function pg_temp.invite_id(p_label text)
returns uuid
language sql
stable
as $$
    select id from pg_temp.mistia_test_invites where label = p_label
$$;

create or replace function pg_temp.invite_token(p_label text)
returns text
language sql
stable
as $$
    select token from pg_temp.mistia_test_invites where label = p_label
$$;

create or replace function pg_temp.store_invite(p_label text, p_invite public.family_invites)
returns void
language plpgsql
as $$
begin
    insert into pg_temp.mistia_test_invites(label, id, token)
    values (p_label, p_invite.id, p_invite.token)
    on conflict (label) do update
    set id = excluded.id,
        token = excluded.token;
end;
$$;

insert into pg_temp.mistia_test_users(label, id)
values
    ('owner', '00000000-0000-4000-8000-000000000001'),
    ('owner_two', '00000000-0000-4000-8000-000000000002'),
    ('member', '00000000-0000-4000-8000-000000000003'),
    ('member_two', '00000000-0000-4000-8000-000000000004'),
    ('other_family_member', '00000000-0000-4000-8000-000000000005'),
    ('kid', '00000000-0000-4000-8000-000000000006'),
    ('stranger', '00000000-0000-4000-8000-000000000007');

insert into auth.users (
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
select
    id,
    'authenticated',
    'authenticated',
    label || '@mistia.test',
    '',
    timezone('utc'::text, now()),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
from pg_temp.mistia_test_users
on conflict (id) do nothing;

insert into public.user_profiles(user_id, display_name)
select id, label
from pg_temp.mistia_test_users
on conflict (user_id) do update
set display_name = excluded.display_name;

do $$
declare
    family_uuid uuid;
begin
    insert into public.families(name, owner_user_id)
    values ('Mistia Quota Test', pg_temp.user_id('owner'))
    returning id into family_uuid;
    insert into pg_temp.mistia_test_families(label, id) values ('quota', family_uuid);
    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (family_uuid, pg_temp.user_id('owner'), 'owner', true, true, true, true, true, true, true);

    insert into public.families(name, owner_user_id)
    values ('Mistia Accept Test', pg_temp.user_id('owner'))
    returning id into family_uuid;
    insert into pg_temp.mistia_test_families(label, id) values ('accept', family_uuid);
    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (family_uuid, pg_temp.user_id('owner'), 'owner', true, true, true, true, true, true, true);

    insert into public.families(name, owner_user_id)
    values ('Mistia Decline Test', pg_temp.user_id('owner'))
    returning id into family_uuid;
    insert into pg_temp.mistia_test_families(label, id) values ('decline', family_uuid);
    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (family_uuid, pg_temp.user_id('owner'), 'owner', true, true, true, true, true, true, true);

    insert into public.families(name, owner_user_id)
    values ('Mistia Status Test', pg_temp.user_id('owner'))
    returning id into family_uuid;
    insert into pg_temp.mistia_test_families(label, id) values ('status', family_uuid);
    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (family_uuid, pg_temp.user_id('owner'), 'owner', true, true, true, true, true, true, true);

    insert into public.families(name, owner_user_id)
    values ('Mistia Other Family Test', pg_temp.user_id('owner_two'))
    returning id into family_uuid;
    insert into pg_temp.mistia_test_families(label, id) values ('other', family_uuid);
    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values
        (family_uuid, pg_temp.user_id('owner_two'), 'owner', true, true, true, true, true, true, true),
        (family_uuid, pg_temp.user_id('other_family_member'), 'member', true, true, false, true, true, false, false);

    insert into public.families(name, owner_user_id)
    values ('Mistia Role Test', pg_temp.user_id('owner'))
    returning id into family_uuid;
    insert into pg_temp.mistia_test_families(label, id) values ('role', family_uuid);
    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (family_uuid, pg_temp.user_id('owner'), 'owner', true, true, true, true, true, true, true);
end;
$$;

select ok(
    exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'family_invites'
          and column_name = 'declined_at'
    ),
    'family_invites has declined_at'
);

select ok(
    exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'family_invites'
          and column_name = 'declined_by_user_id'
    ),
    'family_invites has declined_by_user_id'
);

select ok(to_regprocedure('public.decline_family_invite(text)') is not null, 'decline_family_invite RPC exists');

do $$ begin
    perform pg_temp.set_actor(null);
end $$;

select ok(
    pg_temp.raises_like('select * from public.preview_family_invite(''missing-token'')', '%dang nhap%')
    or pg_temp.raises_like('select * from public.preview_family_invite(''missing-token'')', '%đăng nhập%'),
    'preview requires an authenticated actor'
);

select ok(
    pg_temp.raises_like('select * from public.accept_family_invite(''missing-token'')', '%dang nhap%')
    or pg_temp.raises_like('select * from public.accept_family_invite(''missing-token'')', '%đăng nhập%'),
    'accept requires an authenticated actor'
);

select ok(
    pg_temp.raises_like('select * from public.decline_family_invite(''missing-token'')', '%dang nhap%')
    or pg_temp.raises_like('select * from public.decline_family_invite(''missing-token'')', '%đăng nhập%'),
    'decline requires an authenticated actor'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('role'), '', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('blank-role', created_invite);

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('role'), 'kid', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('kid-role', created_invite);
end;
$$;

select is(
    (select default_role from public.family_invites where id = pg_temp.invite_id('blank-role')),
    'member',
    'blank invite role normalizes to member'
);

select is(
    (select default_role from public.family_invites where id = pg_temp.invite_id('kid-role')),
    'kid',
    'kid invite role is supported'
);

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));
end $$;

select ok(
    pg_temp.raises_like(
        format(
            'select * from public.create_family_invite_link(%L::uuid, %L, %L::timestamptz)',
            pg_temp.family_id('role')::text,
            'owner',
            (timezone('utc'::text, now()) + interval '7 days')::text
        ),
        '%owner%'
    ),
    'owner invite role is rejected'
);

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('member'));
end $$;

select ok(
    pg_temp.raises_like(
        format(
            'select * from public.create_family_invite_link(%L::uuid, %L, %L::timestamptz)',
            pg_temp.family_id('role')::text,
            'member',
            (timezone('utc'::text, now()) + interval '7 days')::text
        ),
        '%chủ sở hữu%'
    ),
    'non-owner cannot create invite links'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('quota'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('quota-one', created_invite);

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('quota'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('quota-two', created_invite);
end;
$$;

select is(
    (
        select count(*)::integer
        from public.family_invites
        where family_id = pg_temp.family_id('quota')
          and accepted_at is null
          and declined_at is null
          and revoked_at is null
          and deleted_at is null
          and expires_at >= timezone('utc'::text, now())
    ),
    2,
    'owner can have two active pending invites'
);

select ok(
    pg_temp.raises_like(
        format(
            'select * from public.create_family_invite_link(%L::uuid, %L, %L::timestamptz)',
            pg_temp.family_id('quota')::text,
            'member',
            (timezone('utc'::text, now()) + interval '7 days')::text
        ),
        '%2 lời mời%'
    ),
    'third active pending invite is blocked'
);

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('member'));
end $$;

select is(
    (select status from public.preview_family_invite('  ' || pg_temp.invite_token('quota-one') || '  ')),
    'pending',
    'preview trims token and shows pending'
);

select is(
    (select family_id::text from public.preview_family_invite(pg_temp.invite_token('quota-one'))),
    pg_temp.family_id('quota')::text,
    'preview returns invited family'
);

do $$
begin
    perform pg_temp.set_actor(pg_temp.user_id('member'));
    perform public.accept_family_invite(pg_temp.invite_token('quota-one'));
end;
$$;

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));
    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('quota'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('quota-after-accept', created_invite);
end;
$$;

select is(
    (
        select count(*)::integer
        from public.family_invites
        where family_id = pg_temp.family_id('quota')
          and accepted_at is null
          and declined_at is null
          and revoked_at is null
          and deleted_at is null
          and expires_at >= timezone('utc'::text, now())
    ),
    2,
    'accepted invites release quota and replacement is active'
);

do $$
begin
    perform pg_temp.set_actor(pg_temp.user_id('member_two'));
    perform public.decline_family_invite(pg_temp.invite_token('quota-two'));
end;
$$;

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));
    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('quota'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('quota-after-decline', created_invite);
end;
$$;

select is(
    (
        select count(*)::integer
        from public.family_invites
        where family_id = pg_temp.family_id('quota')
          and accepted_at is null
          and declined_at is null
          and revoked_at is null
          and deleted_at is null
          and expires_at >= timezone('utc'::text, now())
    ),
    2,
    'declined invites release quota and replacement is active'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));
    perform public.revoke_family_invite(pg_temp.invite_id('quota-after-accept'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('quota'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('quota-after-revoke', created_invite);
end;
$$;

select is(
    (
        select count(*)::integer
        from public.family_invites
        where family_id = pg_temp.family_id('quota')
          and accepted_at is null
          and declined_at is null
          and revoked_at is null
          and deleted_at is null
          and expires_at >= timezone('utc'::text, now())
    ),
    2,
    'revoked invites release quota and replacement is active'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));
    update public.family_invites
    set deleted_at = timezone('utc'::text, now())
    where id = pg_temp.invite_id('quota-after-decline');

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('quota'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('quota-after-delete', created_invite);
end;
$$;

select is(
    (
        select count(*)::integer
        from public.family_invites
        where family_id = pg_temp.family_id('quota')
          and accepted_at is null
          and declined_at is null
          and revoked_at is null
          and deleted_at is null
          and expires_at >= timezone('utc'::text, now())
    ),
    2,
    'deleted invites release quota and replacement is active'
);

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('stranger'));
end $$;

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('status'), 'member', timezone('utc'::text, now()) - interval '1 hour');
    perform pg_temp.store_invite('expired', created_invite);

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('status'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('status-active-one', created_invite);

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('status'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('status-active-two', created_invite);
end;
$$;

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('stranger'));
end $$;

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('expired'))),
    'expired',
    'expired invite previews as expired'
);

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));
end $$;

select ok(
    pg_temp.raises_like(
        format(
            'select * from public.create_family_invite_link(%L::uuid, %L, %L::timestamptz)',
            pg_temp.family_id('status')::text,
            'member',
            (timezone('utc'::text, now()) + interval '7 days')::text
        ),
        '%2 lời mời%'
    ),
    'expired invite does not count, but two active status invites still block third'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('accept'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('accept-main', created_invite);
end;
$$;

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('kid'));
end $$;

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('accept-main'))),
    'pending',
    'accept flow starts pending'
);

select is(
    (select already_member_of_family::text from public.preview_family_invite(pg_temp.invite_token('accept-main'))),
    'false',
    'new invitee is not already a member before accept'
);

do $$
begin
    perform pg_temp.set_actor(pg_temp.user_id('kid'));
    perform public.accept_family_invite(pg_temp.invite_token('accept-main'));
end;
$$;

select ok(
    exists (
        select 1
        from public.family_memberships
        where family_id = pg_temp.family_id('accept')
          and user_id = pg_temp.user_id('kid')
          and role = 'member'
          and can_view_family_dashboard
          and can_view_others
          and not can_edit_others
          and can_view_wallets
          and can_view_debts
          and not can_view_kids
          and not can_edit_kids
          and deleted_at is null
    ),
    'accept creates member membership with expected policy'
);

select ok(
    exists (
        select 1
        from public.family_invites
        where id = pg_temp.invite_id('accept-main')
          and accepted_at is not null
          and accepted_by_user_id = pg_temp.user_id('kid')
    ),
    'accept stamps accepted_at and accepted_by_user_id'
);

select ok(
    exists (
        select 1
        from public.family_notifications
        where family_id = pg_temp.family_id('accept')
          and user_id = pg_temp.user_id('owner')
          and actor_user_id = pg_temp.user_id('kid')
          and kind = 'family_activity'
          and action_state = 'informational'
    ),
    'accept writes owner activity notification'
);

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('accept-main'))),
    'accepted',
    'accepted invite previews as accepted for joined member'
);

select is(
    (select already_member_of_family::text from public.preview_family_invite(pg_temp.invite_token('accept-main'))),
    'true',
    'accepted member previews already_member_of_family'
);

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('member_two'));
end $$;

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('accept-main'))),
    'accepted',
    'used invite previews as accepted for another user'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.accept_family_invite(%L)', pg_temp.invite_token('accept-main')),
        '%được sử dụng%'
    ),
    'used invite cannot be accepted again'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('accept'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('already-member', created_invite);
end;
$$;

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('kid'));
end $$;

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('already-member'))),
    'accepted',
    'pending invite previews accepted when actor already belongs to same family'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('decline'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('decline-main', created_invite);
end;
$$;

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('member_two'));
end $$;

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('decline-main'))),
    'pending',
    'decline flow starts pending'
);

do $$
begin
    perform pg_temp.set_actor(pg_temp.user_id('member_two'));
    perform public.decline_family_invite(pg_temp.invite_token('decline-main'));
end;
$$;

select ok(
    exists (
        select 1
        from public.family_invites
        where id = pg_temp.invite_id('decline-main')
          and declined_at is not null
          and declined_by_user_id = pg_temp.user_id('member_two')
          and accepted_at is null
    ),
    'decline stamps declined_at and declined_by_user_id'
);

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('decline-main'))),
    'declined',
    'declined invite reopens as declined'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.accept_family_invite(%L)', pg_temp.invite_token('decline-main')),
        '%từ chối%'
    ),
    'declined invite cannot be accepted'
);

do $$
begin
    perform pg_temp.set_actor(pg_temp.user_id('stranger'));
    perform public.decline_family_invite(pg_temp.invite_token('decline-main'));
end;
$$;

select is(
    (select declined_by_user_id::text from public.family_invites where id = pg_temp.invite_id('decline-main')),
    pg_temp.user_id('member_two')::text,
    're-decline is idempotent and keeps original declined_by_user_id'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('decline'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('own-link', created_invite);
end;
$$;

select is(
    (select inviter_user_id::text from public.preview_family_invite(pg_temp.invite_token('own-link'))),
    pg_temp.user_id('owner')::text,
    'own-link preview exposes inviter as owner'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.accept_family_invite(%L)', pg_temp.invite_token('own-link')),
        '%không khả dụng%'
    ),
    'owner cannot accept own invite link'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.decline_family_invite(%L)', pg_temp.invite_token('own-link')),
        '%không khả dụng%'
    ),
    'owner cannot decline own invite link'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('decline'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('belongs-other', created_invite);
end;
$$;

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('other_family_member'));
end $$;

select is(
    (select belongs_to_another_family::text from public.preview_family_invite(pg_temp.invite_token('belongs-other'))),
    'true',
    'preview flags actor who belongs to another family'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.accept_family_invite(%L)', pg_temp.invite_token('belongs-other')),
        '%gia đình khác%'
    ),
    'actor in another family cannot accept invite'
);

do $$
declare
    created_invite public.family_invites;
begin
    perform pg_temp.set_actor(pg_temp.user_id('owner'));

    select *
    into created_invite
    from public.create_family_invite_link(pg_temp.family_id('accept'), 'member', timezone('utc'::text, now()) + interval '7 days');
    perform pg_temp.store_invite('revoked', created_invite);

    perform public.revoke_family_invite(created_invite.id);
end;
$$;

do $$ begin
    perform pg_temp.set_actor(pg_temp.user_id('stranger'));
end $$;

select is(
    (select status from public.preview_family_invite(pg_temp.invite_token('revoked'))),
    'revoked',
    'revoked invite previews as revoked'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.accept_family_invite(%L)', pg_temp.invite_token('revoked')),
        '%thu hồi%'
    ),
    'revoked invite cannot be accepted'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.decline_family_invite(%L)', pg_temp.invite_token('revoked')),
        '%thu hồi%'
    ),
    'revoked invite cannot be declined'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.accept_family_invite(%L)', pg_temp.invite_token('expired')),
        '%hết hạn%'
    ),
    'expired invite cannot be accepted'
);

select ok(
    pg_temp.raises_like(
        format('select * from public.decline_family_invite(%L)', pg_temp.invite_token('expired')),
        '%hết hạn%'
    ),
    'expired invite cannot be declined'
);

select ok(
    pg_temp.raises_like('select * from public.preview_family_invite(''not-a-real-token'')', '%hợp lệ%'),
    'invalid token cannot be previewed'
);

select ok(
    pg_temp.raises_like('select * from public.accept_family_invite(''not-a-real-token'')', '%hợp lệ%'),
    'invalid token cannot be accepted'
);

select ok(
    pg_temp.raises_like('select * from public.decline_family_invite(''not-a-real-token'')', '%hợp lệ%'),
    'invalid token cannot be declined'
);

select * from finish();

rollback;
