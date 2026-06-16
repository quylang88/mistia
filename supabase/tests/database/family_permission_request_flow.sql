begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select no_plan();

create temp table mistia_test_users (
    label text primary key,
    id uuid not null
);

create temp table mistia_permission_cases (
    label text primary key,
    resource_type text not null,
    resource_id uuid,
    permission_scope text not null,
    requester_label text not null default 'requester',
    should_approve boolean not null default true
);

create temp table mistia_permission_requests (
    label text primary key,
    request_id uuid not null,
    resource_type text not null,
    resource_id uuid,
    permission_scope text not null,
    requester_user_id uuid not null,
    should_approve boolean not null
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

create or replace function pg_temp.user_id(p_label text)
returns uuid
language sql
stable
as $$
    select id from pg_temp.mistia_test_users where label = p_label
$$;

insert into pg_temp.mistia_test_users(label, id)
values
    ('owner', '10000000-0000-4000-8000-000000000001'),
    ('requester', '10000000-0000-4000-8000-000000000002'),
    ('rejected_requester', '10000000-0000-4000-8000-000000000003');

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
    label || '@mistia.permission.test',
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
    family_uuid uuid := '10000000-0000-4000-8000-000000000101';
    wallet_uuid uuid := '10000000-0000-4000-8000-000000000201';
    category_uuid uuid := '10000000-0000-4000-8000-000000000301';
begin
    insert into public.families(id, name, owner_user_id)
    values (family_uuid, 'Mistia Permission Test', pg_temp.user_id('owner'))
    on conflict (id) do update
    set name = excluded.name,
        owner_user_id = excluded.owner_user_id;

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
        (family_uuid, pg_temp.user_id('owner'), 'owner', true, true, true, true, true, true, true),
        (family_uuid, pg_temp.user_id('requester'), 'member', true, true, false, true, true, false, false),
        (family_uuid, pg_temp.user_id('rejected_requester'), 'member', true, true, false, true, true, false, false);

    insert into public.ledger_wallets (
        id,
        user_id,
        name,
        kind_raw_value,
        icon_symbol_name,
        icon_color_hex,
        currency_code,
        opening_balance_minor
    )
    values (
        wallet_uuid,
        pg_temp.user_id('owner'),
        'Owner Wallet',
        'cash',
        'wallet.pass',
        '#7C3AED',
        'JPY',
        0
    )
    on conflict (id) do update
    set user_id = excluded.user_id,
        name = excluded.name;

    insert into public.transaction_categories (
        id,
        user_id,
        name,
        kind_raw_value,
        icon_symbol_name,
        icon_color_hex
    )
    values (
        category_uuid,
        pg_temp.user_id('owner'),
        'Owner Category',
        'expense',
        'tag',
        '#0EA5E9'
    )
    on conflict (id) do update
    set user_id = excluded.user_id,
        name = excluded.name;
end;
$$;

insert into pg_temp.mistia_permission_cases(label, resource_type, resource_id, permission_scope)
values
    ('edit transaction', 'transaction', null, 'edit'),
    ('edit wallet', 'wallet', '10000000-0000-4000-8000-000000000201', 'edit'),
    ('edit category', 'category', null, 'edit'),
    ('edit budget', 'budget', null, 'edit'),
    ('edit bill', 'bill', null, 'edit'),
    ('edit credit card', 'card', null, 'edit'),
    ('edit debt', 'debt', null, 'edit'),
    ('edit installment', 'installment', null, 'edit'),
    ('create wallet', 'wallet', null, 'create'),
    ('create category', 'category', null, 'create'),
    ('create budget', 'budget', null, 'create'),
    ('create bill', 'bill', null, 'create'),
    ('create credit card', 'card', null, 'create'),
    ('create debt', 'debt', null, 'create'),
    ('create family transfer', 'family_transfer', null, 'create'),
    ('create installment', 'installment', null, 'create');

insert into pg_temp.mistia_permission_cases(
    label,
    resource_type,
    resource_id,
    permission_scope,
    requester_label,
    should_approve
)
values ('reject category create', 'category', null, 'create', 'rejected_requester', false);

select ok(
    to_regprocedure('public.create_family_permission_request(uuid, uuid, text, uuid, text, text, text, text)') is not null,
    'create_family_permission_request RPC signature exists'
);

select ok(
    to_regprocedure('public.respond_family_permission_request(uuid, boolean)') is not null,
    'respond_family_permission_request RPC signature exists'
);

do $$
declare
    family_uuid uuid := '10000000-0000-4000-8000-000000000101';
    permission_case record;
    request_row public.family_permission_requests;
begin
    for permission_case in
        select *
        from pg_temp.mistia_permission_cases
        order by label
    loop
        perform pg_temp.set_actor(pg_temp.user_id(permission_case.requester_label));

        select *
        into request_row
        from public.create_family_permission_request(
            family_uuid,
            pg_temp.user_id('owner'),
            permission_case.resource_type,
            permission_case.resource_id,
            permission_case.permission_scope,
            'Permission request',
            'Please approve this permission request.',
            null
        );

        insert into pg_temp.mistia_permission_requests(
            label,
            request_id,
            resource_type,
            resource_id,
            permission_scope,
            requester_user_id,
            should_approve
        )
        values (
            permission_case.label,
            request_row.id,
            permission_case.resource_type,
            permission_case.resource_id,
            permission_case.permission_scope,
            pg_temp.user_id(permission_case.requester_label),
            permission_case.should_approve
        );

        perform pg_temp.set_actor(pg_temp.user_id('owner'));
        perform public.respond_family_permission_request(request_row.id, permission_case.should_approve);
    end loop;
end;
$$;

select is(
    (
        select count(*)::integer
        from public.family_permission_requests fpr
        join pg_temp.mistia_permission_requests r
          on r.request_id = fpr.id
        where fpr.recipient_user_id = pg_temp.user_id('owner')
          and fpr.resource_type = r.resource_type
          and fpr.resource_id is not distinct from r.resource_id
          and fpr.permission_scope = r.permission_scope
          and fpr.status = case when r.should_approve then 'approved' else 'rejected' end
    ),
    (select count(*)::integer from pg_temp.mistia_permission_requests),
    'all edit/create RPC requests persist with final response status'
);

select is(
    (
        select count(*)::integer
        from public.family_notifications n
        join pg_temp.mistia_permission_requests r
          on r.request_id = n.permission_request_id
        where n.user_id = pg_temp.user_id('owner')
          and n.kind = 'permission_request_received'
          and n.action_state = case when r.should_approve then 'approved' else 'rejected' end
          and n.resource_type = r.resource_type
          and n.resource_id is not distinct from r.resource_id
          and n.permission_scope = r.permission_scope
    ),
    (select count(*)::integer from pg_temp.mistia_permission_requests),
    'each edit/create request creates a recipient notification and response updates it'
);

select is(
    (
        select count(*)::integer
        from public.family_permission_grants g
        join pg_temp.mistia_permission_requests r
          on g.grantee_user_id = r.requester_user_id
         and g.owner_user_id = pg_temp.user_id('owner')
         and g.resource_type = r.resource_type
         and g.resource_id is not distinct from r.resource_id
         and g.permission_scope = r.permission_scope
        where r.should_approve
          and g.revoked_at is null
    ),
    (select count(*)::integer from pg_temp.mistia_permission_requests where should_approve),
    'approved edit/create requests create matching permission grants'
);

select is(
    (
        select count(*)::integer
        from public.family_permission_grants g
        join pg_temp.mistia_permission_requests r
          on g.grantee_user_id = r.requester_user_id
         and g.owner_user_id = pg_temp.user_id('owner')
         and g.resource_type = r.resource_type
         and g.resource_id is not distinct from r.resource_id
         and g.permission_scope = r.permission_scope
        where not r.should_approve
          and g.revoked_at is null
    ),
    0,
    'rejected edit/create requests do not create grants'
);

select is(
    (
        select count(*)::integer
        from public.family_notifications n
        join pg_temp.mistia_permission_requests r
          on r.request_id = n.permission_request_id
        where n.user_id = r.requester_user_id
          and n.kind = case when r.should_approve then 'permission_request_approved' else 'permission_request_rejected' end
          and n.action_state = case when r.should_approve then 'approved' else 'rejected' end
    ),
    (select count(*)::integer from pg_temp.mistia_permission_requests),
    'each response sends a result notification back to the requester'
);

select * from finish();

rollback;
