begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select no_plan();

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
        '30000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
        'investment-owner@mistia.test', '', timezone('utc'::text, now()),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        timezone('utc'::text, now()), timezone('utc'::text, now())
    ),
    (
        '30000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
        'investment-family-owner@mistia.test', '', timezone('utc'::text, now()),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        timezone('utc'::text, now()), timezone('utc'::text, now())
    )
on conflict (id) do nothing;

insert into public.user_profiles(user_id, display_name)
values
    ('30000000-0000-4000-8000-000000000001', 'Investment owner'),
    ('30000000-0000-4000-8000-000000000002', 'Family owner')
on conflict (user_id) do update set display_name = excluded.display_name;

insert into public.families(id, name, owner_user_id)
values (
    '30000000-0000-4000-8000-000000000010',
    'Investment privacy test',
    '30000000-0000-4000-8000-000000000002'
);

insert into public.family_memberships(
    family_id, user_id, role, can_view_family_dashboard, can_view_others,
    can_edit_others, can_view_wallets, can_view_debts, can_view_kids, can_edit_kids
)
values
    (
        '30000000-0000-4000-8000-000000000010',
        '30000000-0000-4000-8000-000000000002',
        'owner', true, true, true, true, true, true, true
    ),
    (
        '30000000-0000-4000-8000-000000000010',
        '30000000-0000-4000-8000-000000000001',
        'member', true, true, false, true, true, false, false
    );

select pg_temp.set_actor('30000000-0000-4000-8000-000000000001');

insert into public.ledger_wallets(
    id, user_id, name, kind_raw_value, icon_symbol_name, icon_color_hex,
    currency_code, opening_balance_minor, system_purpose_raw_value
)
values (
    public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001'),
    '30000000-0000-4000-8000-000000000001',
    'Ignored', 'cash', 'banknote.fill', '#000000', 'JPY', 999,
    'investmentProfit'
);

insert into public.ledger_wallets(
    id, user_id, name, kind_raw_value, icon_symbol_name, icon_color_hex,
    currency_code, opening_balance_minor
)
values
    (
        '30000000-0000-4000-8000-000000000101',
        '30000000-0000-4000-8000-000000000001',
        'Funding', 'cash', 'banknote.fill', '#111111', 'JPY', 1000
    ),
    (
        '30000000-0000-4000-8000-000000000102',
        '30000000-0000-4000-8000-000000000001',
        'Capital return', 'bank', 'building.columns.fill', '#222222', 'JPY', 0
    );

insert into public.investment_channels(
    id, user_id, name, icon_symbol_name, icon_color_hex
)
values (
    '30000000-0000-4000-8000-000000000201',
    '30000000-0000-4000-8000-000000000001',
    'Pokémon', 'shippingbox.fill', '#9A67FF'
);

insert into public.investment_assets(
    id, user_id, channel_id, name, currency_code
)
values (
    '30000000-0000-4000-8000-000000000301',
    '30000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000201',
    'Card A', 'JPY'
);

select hasnt_column('public', 'investment_assets', 'symbol', 'asset symbol is removed');
select hasnt_column('public', 'investment_assets', 'opening_quantity_decimal_string', 'asset opening quantity is removed');
select hasnt_column('public', 'investment_assets', 'opening_cost_minor', 'asset opening capital is removed');
select hasnt_column('public', 'investment_trades', 'fee_minor', 'trade fee is removed');
select hasnt_column('public', 'investment_trades', 'accounting_fee_minor', 'accounting fee is removed');

select is(
    (select name from public.ledger_wallets where system_purpose_raw_value = 'investmentProfit'),
    'Investment Wallet',
    'system Investment Wallet basic metadata is canonicalized'
);

select is(
    (select opening_balance_minor from public.ledger_wallets where system_purpose_raw_value = 'investmentProfit'),
    0::bigint,
    'system Investment Wallet cannot carry opening capital'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000401',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000301',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '3',
            'gross_amount_minor', 120,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 120,
            'accounting_currency_code', 'JPY',
            'funding_wallet_id', '30000000-0000-4000-8000-000000000101',
            'occurred_at', '2026-08-09T00:00:00Z',
            'created_at', '2026-08-09T00:00:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'buy is accepted atomically'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000402',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000301',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '3',
            'gross_amount_minor', 150,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 150,
            'accounting_currency_code', 'JPY',
            'capital_return_wallet_id', '30000000-0000-4000-8000-000000000102',
            'occurred_at', '2026-08-09T00:00:01Z',
            'created_at', '2026-08-09T00:00:01Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'sale is accepted atomically'
);

select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000101'),
    880::bigint,
    'buy removes the total order amount once, without multiplying by quantity'
);

select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000102'),
    120::bigint,
    'sale returns exactly the released cost basis to the ordinary wallet'
);

select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    30::bigint,
    'sale profit is isolated in the Investment Wallet'
);

select is(
    (
        select realized_profit_loss_minor from public.investment_trades
        where id = '30000000-0000-4000-8000-000000000402'
    ),
    30::bigint,
    'weighted-average accounting realizes the expected profit'
);

select is(
    (
        select coalesce(sum(reporting_expense_minor), 0) + coalesce(sum(reporting_income_minor), 0)
        from public.ledger_transactions
        where user_id = '30000000-0000-4000-8000-000000000001'
          and settlement_role_raw_value like 'investment%'
          and deleted_at is null
    )::bigint,
    0::bigint,
    'investment ledger legs never enter ordinary income or expense reporting'
);

select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000403',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000301',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '1',
            'gross_amount_minor', 200,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 200,
            'accounting_currency_code', 'JPY',
            'capital_return_wallet_id', '30000000-0000-4000-8000-000000000102',
            'occurred_at', '2026-08-09T00:00:02Z',
            'created_at', '2026-08-09T00:00:02Z'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Sale exceeds the quantity held',
    'overselling rolls back the entire RPC'
);

select pg_temp.set_actor('30000000-0000-4000-8000-000000000002');

select ok(
    not public.has_investment_permission('30000000-0000-4000-8000-000000000001', 'view'),
    'family owner role alone cannot view another member investment data'
);

create temp table mistia_investment_view_request as
select id
from public.create_family_permission_request(
    '30000000-0000-4000-8000-000000000010',
    '30000000-0000-4000-8000-000000000001',
    'investment',
    null,
    'view',
    'Investment access request',
    'Please approve investment access.',
    null
);

select is(
    (
        select count(*)::integer
        from public.family_notifications notification
        where notification.permission_request_id = (
            select id from pg_temp.mistia_investment_view_request
        )
          and notification.action_state = 'pending'
    ),
    1,
    'investment View request creates an actionable owner notification'
);

select pg_temp.set_actor('30000000-0000-4000-8000-000000000001');

select lives_ok(
    $$
    select public.respond_family_permission_request(
        (select id from pg_temp.mistia_investment_view_request),
        true
    )
    $$,
    'investment owner can approve the View request'
);

insert into public.family_permission_grants(
    family_id, grantee_user_id, owner_user_id, resource_type, resource_id, permission_scope, granted_by_user_id
)
values (
    '30000000-0000-4000-8000-000000000010',
    '30000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001',
    'investment', null, 'create',
    '30000000-0000-4000-8000-000000000001'
);

select pg_temp.set_actor('30000000-0000-4000-8000-000000000002');

select ok(
    public.has_investment_permission('30000000-0000-4000-8000-000000000001', 'view'),
    'explicit View grant unlocks investment visibility'
);

select ok(
    public.has_investment_permission('30000000-0000-4000-8000-000000000001', 'create'),
    'Create remains independent and requires active View'
);

select ok(
    not public.has_investment_permission('30000000-0000-4000-8000-000000000001', 'edit'),
    'Edit is not implied by View or Create'
);

reset role;
select pg_temp.set_actor('30000000-0000-4000-8000-000000000001');

update public.family_permission_grants
set revoked_at = timezone('utc'::text, now())
where owner_user_id = '30000000-0000-4000-8000-000000000001'
  and grantee_user_id = '30000000-0000-4000-8000-000000000002'
  and resource_type = 'investment'
  and permission_scope = 'view';

select is(
    (
        select count(*)::integer from public.family_permission_grants
        where owner_user_id = '30000000-0000-4000-8000-000000000001'
          and grantee_user_id = '30000000-0000-4000-8000-000000000002'
          and resource_type = 'investment'
          and permission_scope in ('create', 'edit')
          and revoked_at is null
    ),
    0,
    'revoking View also revokes dependent Create and Edit grants'
);

select * from finish();

rollback;
