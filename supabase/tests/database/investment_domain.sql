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
    ),
    (
        '30000000-0000-4000-8000-000000000103',
        '30000000-0000-4000-8000-000000000001',
        'Second funding', 'bank', 'building.columns.fill', '#333333', 'JPY', 1000
    ),
    (
        '30000000-0000-4000-8000-000000000104',
        '30000000-0000-4000-8000-000000000001',
        'Low balance', 'cash', 'banknote.fill', '#444444', 'JPY', 50
    ),
    (
        '30000000-0000-4000-8000-000000000105',
        '30000000-0000-4000-8000-000000000001',
        'Second capital return', 'bank', 'building.columns.fill', '#555555', 'JPY', 0
    ),
    (
        '30000000-0000-4000-8000-000000000106',
        '30000000-0000-4000-8000-000000000001',
        'FIFO funding', 'cash', 'banknote.fill', '#666666', 'JPY', 1000
    ),
    (
        '30000000-0000-4000-8000-000000000107',
        '30000000-0000-4000-8000-000000000001',
        'FIFO capital return', 'bank', 'building.columns.fill', '#777777', 'JPY', 0
    );

insert into public.investment_channels(
    id, user_id, name, icon_symbol_name, icon_color_hex
)
values
    (
        '30000000-0000-4000-8000-000000000201',
        '30000000-0000-4000-8000-000000000001',
        'Pokémon', 'shippingbox.fill', '#9A67FF'
    ),
    (
        '30000000-0000-4000-8000-000000000202',
        '30000000-0000-4000-8000-000000000001',
        'Second shop', 'shippingbox.fill', '#7A5AFF'
    );

insert into public.investment_assets(
    id, user_id, channel_id, name, currency_code
)
values
    (
        '30000000-0000-4000-8000-000000000301',
        '30000000-0000-4000-8000-000000000001',
        '30000000-0000-4000-8000-000000000201',
        'Card A', 'JPY'
    ),
    (
        '30000000-0000-4000-8000-000000000302',
        '30000000-0000-4000-8000-000000000001',
        '30000000-0000-4000-8000-000000000202',
        'Card B', 'JPY'
    ),
    (
        '30000000-0000-4000-8000-000000000303',
        '30000000-0000-4000-8000-000000000001',
        '30000000-0000-4000-8000-000000000201',
        'FIFO card', 'JPY'
    );

select hasnt_column('public', 'investment_assets', 'symbol', 'asset symbol is removed');
select hasnt_column('public', 'investment_assets', 'opening_quantity_decimal_string', 'asset opening quantity is removed');
select hasnt_column('public', 'investment_assets', 'opening_cost_minor', 'asset opening capital is removed');
select hasnt_column('public', 'investment_trades', 'fee_minor', 'trade fee is removed');
select hasnt_column('public', 'investment_trades', 'accounting_fee_minor', 'accounting fee is removed');
select has_column('public', 'investment_assets', 'image_path', 'product image object path is stored on the asset');
select has_column('public', 'investment_assets', 'default_unit_label', 'asset stores an optional default inventory unit');
select has_column('public', 'investment_trades', 'unit_label', 'trade stores an optional inventory unit');
select has_column('public', 'ledger_wallets', 'investment_linked_wallet_id', 'Investment Wallet stores one linked real wallet');
select has_column('public', 'investment_wallet_postings', 'cash_bucket_raw_value', 'posting stores booked or unreconciled cash bucket');
select has_column('public', 'investment_wallet_postings', 'cash_origin_raw_value', 'posting records whether cash allocation is derived, inferred or manual');
select has_function('public', 'mutate_investment_cash_postings', array['jsonb', 'boolean'], 'batch cash mutation RPC is installed');
select hasnt_table('public', 'investment_valuations', 'manual investment valuations are removed');
select is(
    (
        select count(*)::bigint
        from information_schema.tables
        where table_schema = 'public'
          and table_name in (
              'investment_channels',
              'investment_assets',
              'investment_trades',
              'investment_wallet_postings'
          )
    ),
    4::bigint,
    'exactly four Investment domain tables remain'
);
select is(
    (select public from storage.buckets where id = 'investment-product-images'),
    false,
    'product image bucket is private'
);

set local role authenticated;
select lives_ok(
    $$
    insert into storage.objects(bucket_id, name, owner_id)
    values (
        'investment-product-images',
        '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000801.jpg',
        '30000000-0000-4000-8000-000000000001'
    )
    $$,
    'Investment owner can upload a private product image'
);
select is(
    (
        select count(*)::bigint
        from storage.objects
        where bucket_id = 'investment-product-images'
          and name = '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000801.jpg'
    ),
    1::bigint,
    'Investment owner can read the private product image'
);
reset role;
select pg_temp.set_actor('30000000-0000-4000-8000-000000000001');

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
    150::bigint,
    'sale credits the full proceeds to the receiving wallet'
);

select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    0::bigint,
    'sale profit does not create a separate virtual wallet balance'
);

select is(
    (
        select realized_profit_loss_minor from public.investment_trades
        where id = '30000000-0000-4000-8000-000000000402'
    ),
    30::bigint,
    'FIFO accounting realizes the expected profit'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000410',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000303',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '2',
            'gross_amount_minor', 200,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 200,
            'accounting_currency_code', 'JPY',
            'funding_wallet_id', '30000000-0000-4000-8000-000000000106',
            'occurred_at', '2026-08-09T00:10:00Z',
            'created_at', '2026-08-09T00:10:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ), null, false
    )
    $$,
    'FIFO first purchase lot is accepted'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000411',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000303',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '1',
            'gross_amount_minor', 150,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 150,
            'accounting_currency_code', 'JPY',
            'funding_wallet_id', '30000000-0000-4000-8000-000000000106',
            'occurred_at', '2026-08-09T00:10:01Z',
            'created_at', '2026-08-09T00:10:01Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ), null, false
    )
    $$,
    'FIFO second purchase lot is accepted'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000412',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000303',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '1',
            'gross_amount_minor', 160,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 160,
            'accounting_currency_code', 'JPY',
            'capital_return_wallet_id', '30000000-0000-4000-8000-000000000107',
            'occurred_at', '2026-08-09T00:10:02Z',
            'created_at', '2026-08-09T00:10:02Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ), null, false
    )
    $$,
    'FIFO sale is accepted across differently priced lots'
);

select is(
    (select released_cost_basis_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000412'),
    100::bigint,
    'FIFO sale releases the oldest purchase cost'
);
select is(
    (select realized_profit_loss_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000412'),
    60::bigint,
    'FIFO sale realizes profit against the oldest purchase cost'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000412'),
    250::bigint,
    'FIFO preserves the remaining cost of the partially consumed and newer lots'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000413',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000303',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '2',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-09T00:10:03Z',
            'created_at', '2026-08-09T00:10:03Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ), null, false
    )
    $$,
    'zero-amount liquidation is accepted without a wallet'
);

select is(
    (select released_cost_basis_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000413'),
    250::bigint,
    'zero-amount liquidation releases all remaining cost basis'
);

select is(
    (select realized_profit_loss_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000413'),
    -250::bigint,
    'zero-amount liquidation records 100% loss'
);

select is(
    (select position_quantity_after_decimal_string from public.investment_trades where id = '30000000-0000-4000-8000-000000000413'),
    '0',
    'zero-amount liquidation clears position quantity'
);

select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000413'),
    0::bigint,
    'zero-amount liquidation clears position cost basis'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000414',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000303',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '3',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-09T00:10:04Z',
            'created_at', '2026-08-09T00:10:04Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ), null, false
    )
    $$,
    'zero-amount promotional buy is accepted without a wallet'
);

select is(
    (select position_quantity_after_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000414'),
    3::numeric,
    'promotional buy adds inventory quantity'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000414'),
    0::bigint,
    'promotional buy adds no invested cost basis'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000106'),
    650::bigint,
    'promotional buy does not debit a wallet'
);
select is(
    (
        select count(*)::bigint from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000414' and deleted_at is null
    ),
    0::bigint,
    'promotional buy creates no wallet posting'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'quantity_decimal_string', '4',
                'gross_amount_minor', 120,
                'accounting_gross_amount_minor', 120,
                'funding_wallet_id', '30000000-0000-4000-8000-000000000106'
            )
            from public.investment_trades trade
            where id = '30000000-0000-4000-8000-000000000414'
        ), null, false
    )
    $$,
    'promotional buy can be edited into a paid buy atomically'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000106'),
    530::bigint,
    'editing promotional inventory into a paid buy debits the exact total once'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000414'),
    120::bigint,
    'paid edit replaces zero cost with the entered total cost basis'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'quantity_decimal_string', '5',
                'gross_amount_minor', 0,
                'accounting_gross_amount_minor', 0,
                'funding_wallet_id', null
            )
            from public.investment_trades trade
            where id = '30000000-0000-4000-8000-000000000414'
        ), null, false
    )
    $$,
    'paid buy can be edited back into promotional inventory atomically'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000106'),
    650::bigint,
    'editing back to promotional inventory fully restores the funding wallet'
);
select is(
    (
        select count(*)::bigint from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000414' and deleted_at is null
    ),
    0::bigint,
    'editing back to promotional inventory removes the old funding posting'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000415',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000303',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '2',
            'gross_amount_minor', 80,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 80,
            'accounting_currency_code', 'JPY',
            'capital_return_wallet_id', '30000000-0000-4000-8000-000000000107',
            'occurred_at', '2026-08-09T00:10:05Z',
            'created_at', '2026-08-09T00:10:05Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ), null, false
    )
    $$,
    'sale of promotional inventory is accepted atomically'
);
select is(
    (select released_cost_basis_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000415'),
    0::bigint,
    'sale of promotional inventory releases zero cost basis'
);
select is(
    (select realized_profit_loss_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000415'),
    80::bigint,
    'all proceeds from promotional inventory become Investment Wallet profit'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000107'),
    240::bigint,
    'sale of promotional inventory adds its full proceeds to the receiving wallet'
);
select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    -250::bigint,
    'promotional sale leaves the prior total-loss balance unchanged'
);

select lives_ok(
    $$
    select * from public.delete_investment_trade(
        '30000000-0000-4000-8000-000000000415',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000415'),
        '2026-08-09T00:10:06Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'promotional inventory sale can be soft deleted atomically'
);
select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    -250::bigint,
    'deleting the promotional sale leaves the prior total-loss balance unchanged'
);

select lives_ok(
    $$
    select * from public.delete_investment_trade(
        '30000000-0000-4000-8000-000000000414',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000414'),
        '2026-08-09T00:10:07Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'promotional buy can be soft deleted atomically'
);
select ok(
    (select deleted_at is not null from public.investment_trades where id = '30000000-0000-4000-8000-000000000414'),
    'promotional buy is soft deleted'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000106'),
    650::bigint,
    'deleting promotional inventory leaves the funding wallet exact'
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
    'Sale exceeds the quantity held for the selected unit',
    'overselling rolls back the entire RPC'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000404',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000301',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '2',
            'gross_amount_minor', 80,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 80,
            'accounting_currency_code', 'JPY',
            'funding_wallet_id', '30000000-0000-4000-8000-000000000101',
            'occurred_at', '2026-08-09T00:00:03Z',
            'created_at', '2026-08-09T00:00:03Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'second buy is created before correction'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000404',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000202',
            'asset_id', '30000000-0000-4000-8000-000000000302',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '4',
            'gross_amount_minor', 200,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 200,
            'accounting_currency_code', 'JPY',
            'funding_wallet_id', '30000000-0000-4000-8000-000000000103',
            'note', 'Corrected buy',
            'occurred_at', '2026-08-09T00:00:04Z',
            'created_at', '2026-08-09T00:00:03Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'buy correction moves the same trade between assets and wallets'
);

select is(
    (select asset_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    '30000000-0000-4000-8000-000000000302'::uuid,
    'edited buy moves to the selected asset'
);
select is(
    (select channel_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    '30000000-0000-4000-8000-000000000202'::uuid,
    'edited buy follows the selected asset channel'
);
select is(
    (select kind_raw_value from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    'buy',
    'edited trade remains a buy'
);
select is(
    (select quantity_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    4::numeric,
    'edited buy stores the corrected quantity'
);
select is(
    (select gross_amount_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    200::bigint,
    'edited buy stores the corrected total amount'
);
select is(
    (select occurred_at from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    '2026-08-09T00:00:04Z'::timestamptz,
    'edited buy stores the corrected date'
);
select is(
    (select funding_wallet_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    '30000000-0000-4000-8000-000000000103'::uuid,
    'edited buy stores the corrected funding wallet'
);
select is(
    (select note from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    'Corrected buy',
    'edited buy stores the corrected note'
);
select is(
    (select position_quantity_after_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    4::numeric,
    'new asset position uses edited quantity'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    200::bigint,
    'new asset capital uses edited total amount'
);
select is(
    (
        select position_quantity_after_decimal_string::numeric
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000301'
          and deleted_at is null
        order by occurred_at desc, created_at desc, id desc
        limit 1
    ),
    0::numeric,
    'old asset position is rebuilt without the moved buy'
);
select is(
    (
        select position_cost_basis_after_minor
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000301'
          and deleted_at is null
        order by occurred_at desc, created_at desc, id desc
        limit 1
    ),
    0::bigint,
    'old asset capital is rebuilt without the moved buy'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000101'),
    880::bigint,
    'old wallet is restored'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000103'),
    800::bigint,
    'new wallet is debited by the edited total'
);
select is(
    (
        select asset_id
        from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000404'
          and deleted_at is null
    ),
    '30000000-0000-4000-8000-000000000302'::uuid,
    'derived posting follows the new asset'
);

select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'kind_raw_value', 'sell',
                'funding_wallet_id', null,
                'capital_return_wallet_id', '30000000-0000-4000-8000-000000000102'
            )
            from public.investment_trades trade
            where trade.id = '30000000-0000-4000-8000-000000000404'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Investment trade kind is immutable',
    'an existing buy cannot become a sell'
);

select is(
    (
        select count(*)::bigint
        from public.mutate_investment_trade(
            (
                select to_jsonb(trade) || jsonb_build_object('note', 'Stale overwrite')
                from public.investment_trades trade
                where trade.id = '30000000-0000-4000-8000-000000000404'
            ),
            (
                select sync_version - 1
                from public.investment_trades
                where id = '30000000-0000-4000-8000-000000000404'
            ),
            false
        )
    ),
    0::bigint,
    'a stale edit returns no trade row'
);
select is(
    (select note from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    'Corrected buy',
    'a stale edit does not overwrite current fields'
);

select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'gross_amount_minor', 500,
                'accounting_gross_amount_minor', 500,
                'funding_wallet_id', '30000000-0000-4000-8000-000000000104'
            )
            from public.investment_trades trade
            where trade.id = '30000000-0000-4000-8000-000000000404'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Insufficient wallet balance',
    'an underfunded edit rolls back the RPC'
);
select is(
    (select gross_amount_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    200::bigint,
    'failed edit leaves the stored amount unchanged'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000103'),
    800::bigint,
    'failed edit leaves the active funding wallet unchanged'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000104'),
    50::bigint,
    'failed edit leaves the rejected wallet unchanged'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000406',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000301',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '2',
            'gross_amount_minor', 100,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 100,
            'accounting_currency_code', 'JPY',
            'funding_wallet_id', '30000000-0000-4000-8000-000000000101',
            'occurred_at', '2026-08-09T00:00:05Z',
            'created_at', '2026-08-09T00:00:05Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'buy is created to cover a sell correction'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000405',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000301',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '1',
            'gross_amount_minor', 150,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 150,
            'accounting_currency_code', 'JPY',
            'capital_return_wallet_id', '30000000-0000-4000-8000-000000000102',
            'occurred_at', '2026-08-09T00:00:06Z',
            'created_at', '2026-08-09T00:00:06Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'sale is created before correction'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000405',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000202',
            'asset_id', '30000000-0000-4000-8000-000000000302',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '3',
            'gross_amount_minor', 260,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 260,
            'accounting_currency_code', 'JPY',
            'capital_return_wallet_id', '30000000-0000-4000-8000-000000000105',
            'note', 'Corrected sale',
            'occurred_at', '2026-08-09T00:00:07Z',
            'created_at', '2026-08-09T00:00:06Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'sale correction moves the same trade between assets and capital wallets'
);

select is(
    (select kind_raw_value from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    'sell',
    'edited sale remains a sale'
);
select is(
    (select asset_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    '30000000-0000-4000-8000-000000000302'::uuid,
    'edited sale moves to the selected asset'
);
select is(
    (select channel_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    '30000000-0000-4000-8000-000000000202'::uuid,
    'edited sale follows the selected asset channel'
);
select is(
    (select quantity_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    3::numeric,
    'edited sale stores the corrected quantity'
);
select is(
    (select gross_amount_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    260::bigint,
    'edited sale stores the corrected total amount'
);
select is(
    (select occurred_at from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    '2026-08-09T00:00:07Z'::timestamptz,
    'edited sale stores the corrected date'
);
select is(
    (select capital_return_wallet_id from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    '30000000-0000-4000-8000-000000000105'::uuid,
    'edited sale stores the corrected capital-return wallet'
);
select is(
    (select note from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    'Corrected sale',
    'edited sale stores the corrected note'
);
select is(
    (
        select position_quantity_after_decimal_string::numeric
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000301'
          and deleted_at is null
        order by occurred_at desc, created_at desc, id desc
        limit 1
    ),
    2::numeric,
    'old asset position is rebuilt without the moved sale'
);
select is(
    (
        select position_cost_basis_after_minor
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000301'
          and deleted_at is null
        order by occurred_at desc, created_at desc, id desc
        limit 1
    ),
    100::bigint,
    'old asset capital is rebuilt without the moved sale'
);
select is(
    (select position_quantity_after_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    1::numeric,
    'new asset position reflects the edited sale'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    50::bigint,
    'new asset capital reflects the edited sale'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000102'),
    150::bigint,
    'old capital-return wallet is restored after moving the sale'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000105'),
    260::bigint,
    'new capital-return wallet receives the full sale proceeds'
);
select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    -250::bigint,
    'moving the sale does not create a virtual Investment Wallet profit balance'
);
select is(
    (
        select count(distinct asset_id)::bigint
        from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000405'
          and deleted_at is null
    ),
    1::bigint,
    'edited sale active postings use one asset'
);
select is(
    (
        select asset_id
        from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000405'
          and deleted_at is null
        limit 1
    ),
    '30000000-0000-4000-8000-000000000302'::uuid,
    'edited sale active postings follow the new asset'
);

select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'kind_raw_value', 'buy',
                'funding_wallet_id', '30000000-0000-4000-8000-000000000101',
                'capital_return_wallet_id', null
            )
            from public.investment_trades trade
            where trade.id = '30000000-0000-4000-8000-000000000405'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Investment trade kind is immutable',
    'an existing sale cannot become a buy'
);

select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object(
                'quantity_decimal_string', '5',
                'gross_amount_minor', 500,
                'accounting_gross_amount_minor', 500
            )
            from public.investment_trades trade
            where trade.id = '30000000-0000-4000-8000-000000000405'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Sale exceeds the quantity held for the selected unit',
    'moving a sale cannot oversell the target asset'
);
select is(
    (select quantity_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    3::numeric,
    'failed oversell leaves sale quantity unchanged'
);
select is(
    (select gross_amount_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    260::bigint,
    'failed oversell leaves sale amount unchanged'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000105'),
    260::bigint,
    'failed oversell leaves the capital-return wallet unchanged'
);

select lives_ok(
    $$
    select * from public.delete_investment_trade(
        '30000000-0000-4000-8000-000000000405',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
        '2026-08-09T00:00:08Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'sale soft delete succeeds through the trade RPC'
);
select ok(
    (select deleted_at is not null from public.investment_trades where id = '30000000-0000-4000-8000-000000000405'),
    'sale is soft deleted'
);
select is(
    (
        select position_quantity_after_decimal_string::numeric
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000302'
          and deleted_at is null
        order by occurred_at desc, created_at desc, id desc
        limit 1
    ),
    4::numeric,
    'deleting the sale restores asset quantity'
);
select is(
    (
        select position_cost_basis_after_minor
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000302'
          and deleted_at is null
        order by occurred_at desc, created_at desc, id desc
        limit 1
    ),
    200::bigint,
    'deleting the sale restores asset capital'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000105'),
    0::bigint,
    'deleting the sale restores the capital-return wallet'
);
select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    -250::bigint,
    'deleting the sale leaves unrelated Investment Wallet loss unchanged'
);
select is(
    (
        select count(*)::bigint
        from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000405'
          and deleted_at is null
    ),
    0::bigint,
    'deleting the sale removes its active postings'
);

select lives_ok(
    $$
    select * from public.delete_investment_trade(
        '30000000-0000-4000-8000-000000000404',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
        '2026-08-09T00:00:09Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'buy soft delete succeeds through the trade RPC'
);
select ok(
    (select deleted_at is not null from public.investment_trades where id = '30000000-0000-4000-8000-000000000404'),
    'buy is soft deleted'
);
select is(
    (
        select count(*)::bigint
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000302'
          and deleted_at is null
    ),
    0::bigint,
    'deleting the buy leaves no active trade on its asset'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000103'),
    1000::bigint,
    'deleting the buy restores its funding wallet'
);
select is(
    (
        select count(*)::bigint
        from public.investment_wallet_postings
        where trade_id = '30000000-0000-4000-8000-000000000404'
          and deleted_at is null
    ),
    0::bigint,
    'deleting the buy removes its active postings'
);

select pg_temp.set_actor('30000000-0000-4000-8000-000000000002');

select ok(
    not public.has_investment_permission('30000000-0000-4000-8000-000000000001', 'view'),
    'family owner role alone cannot view another member investment data'
);

set local role authenticated;
select is(
    (
        select count(*)::bigint
        from storage.objects
        where bucket_id = 'investment-product-images'
          and name = '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000801.jpg'
    ),
    0::bigint,
    'member without Investment View cannot read a private product image'
);
reset role;
select pg_temp.set_actor('30000000-0000-4000-8000-000000000002');

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

set local role authenticated;
select is(
    (
        select count(*)::bigint
        from storage.objects
        where bucket_id = 'investment-product-images'
          and name = '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000801.jpg'
    ),
    1::bigint,
    'member with Investment View can read a private product image'
);
select lives_ok(
    $$
    insert into storage.objects(bucket_id, name, owner_id)
    values (
        'investment-product-images',
        '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000802.jpg',
        '30000000-0000-4000-8000-000000000002'
    )
    $$,
    'member with Investment Create can upload a product image for the owner'
);
update storage.objects
set user_metadata = '{"attempted":"overwrite"}'::jsonb
where bucket_id = 'investment-product-images'
  and name = '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000801.jpg';
select is(
    (
        select user_metadata
        from storage.objects
        where bucket_id = 'investment-product-images'
          and name = '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000301/30000000-0000-4000-8000-000000000801.jpg'
    ),
    null::jsonb,
    'member without Investment Edit cannot replace a product image'
);
select ok(
    (
        select qual like '%has_investment_permission%''edit''%'
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname = 'investment_product_images_delete'
    ),
    'private product image deletion policy requires Investment Edit'
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

select lives_ok(
    $$
    select * from public.mutate_investment_asset(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000304',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'name', '  RPC product  ',
            'currency_code', 'jpy',
            'sort_order', 3,
            'is_archived', false,
            'created_at', '2026-08-22T00:20:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'investment product can be created atomically through RPC'
);
select is(
    (select name from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    'RPC product',
    'asset RPC trims the product name'
);
select is(
    (select currency_code from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    'JPY',
    'asset RPC normalizes the product currency'
);
select is(
    (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    1::bigint,
    'asset RPC creates the first server version'
);

select is(
    (
        select count(*)::bigint
        from public.mutate_investment_asset(
            (
                select to_jsonb(asset) || jsonb_build_object('name', 'Stale product edit')
                from public.investment_assets asset
                where id = '30000000-0000-4000-8000-000000000304'
            ),
            0,
            false
        )
    ),
    0::bigint,
    'stale asset edit returns no row'
);

select lives_ok(
    $$
    select * from public.mutate_investment_asset(
        (
            select to_jsonb(asset) || jsonb_build_object(
                'name', 'RPC product renamed',
                'image_path', '30000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000304/30000000-0000-4000-8000-000000000803.jpg'
            )
            from public.investment_assets asset
            where id = '30000000-0000-4000-8000-000000000304'
        ),
        (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
        false
    )
    $$,
    'asset metadata and image path can be edited atomically through RPC'
);
select is(
    (select name from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    'RPC product renamed',
    'asset metadata edit is stored'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000416',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000304',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '2',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-22T00:21:00Z',
            'created_at', '2026-08-22T00:21:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'FIFO history can be created for an RPC-managed asset'
);

select throws_ok(
    $$
    select * from public.mutate_investment_asset(
        (
            select to_jsonb(asset) || jsonb_build_object('currency_code', 'USD')
            from public.investment_assets asset
            where id = '30000000-0000-4000-8000-000000000304'
        ),
        (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
        false
    )
    $$,
    'P0001',
    'Product channel and currency are immutable after history exists',
    'asset RPC protects FIFO identity after transaction history exists'
);
select is(
    (select currency_code from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    'JPY',
    'failed accounting identity edit leaves the asset unchanged'
);
select is(
    (select position_quantity_after_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
    2::numeric,
    'failed asset edit leaves FIFO quantity unchanged'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
    0::bigint,
    'failed asset edit leaves FIFO cost unchanged'
);

select throws_ok(
    $$
    select * from public.delete_investment_asset(
        '30000000-0000-4000-8000-000000000304',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
        '2026-08-22T00:22:00Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'P0001',
    'Sell all remaining stock before deleting the investment product',
    'asset delete RPC rejects a product with remaining inventory'
);

select lives_ok(
    $$
    select * from public.mutate_investment_asset(
        (
            select to_jsonb(asset) || jsonb_build_object('default_unit_label', '  pack  ')
            from public.investment_assets asset
            where id = '30000000-0000-4000-8000-000000000304'
        ),
        (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
        false
    )
    $$,
    'first asset default unit atomically resolves legacy history'
);
select is(
    (select default_unit_label from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    'pack',
    'asset default unit is trimmed and stored'
);
select is(
    (select unit_label from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
    'pack',
    'legacy unitless trade is backfilled by the asset mutation'
);
select is(
    (select position_quantity_after_decimal_string::numeric from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
    2::numeric,
    'unit backfill preserves aggregate quantity accounting'
);
select is(
    (select position_cost_basis_after_minor from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
    0::bigint,
    'unit backfill preserves aggregate cost accounting'
);

select lives_ok(
    $$
    select * from public.mutate_investment_asset(
        (
            select (to_jsonb(asset) - 'default_unit_label') || jsonb_build_object('name', 'Old client product edit')
            from public.investment_assets asset
            where id = '30000000-0000-4000-8000-000000000304'
        ),
        (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
        false
    )
    $$,
    'old asset payload without the unit key can still edit metadata'
);
select is(
    (select default_unit_label from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    'pack',
    'old asset payload preserves the current default unit'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select (to_jsonb(trade) - 'unit_label') || jsonb_build_object('note', 'Old client trade edit')
            from public.investment_trades trade
            where id = '30000000-0000-4000-8000-000000000416'
        ),
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
        false
    )
    $$,
    'old trade payload without the unit key can still edit an existing trade'
);
select is(
    (select unit_label from public.investment_trades where id = '30000000-0000-4000-8000-000000000416'),
    'pack',
    'old trade payload preserves the current trade unit'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000417',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000304',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '1',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-22T00:23:00Z',
            'created_at', '2026-08-22T00:23:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'new trade from an old app inherits the asset default unit'
);
select is(
    (select unit_label from public.investment_trades where id = '30000000-0000-4000-8000-000000000417'),
    'pack',
    'old-client trade creation stores the asset default unit'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000418',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000304',
            'kind_raw_value', 'buy',
            'quantity_decimal_string', '1',
            'unit_label', '  Box ',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-22T00:24:00Z',
            'created_at', '2026-08-22T00:24:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'a second independent unit can be bought for the same asset'
);
select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000419',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000304',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '1',
            'unit_label', 'box',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-22T00:25:00Z',
            'created_at', '2026-08-22T00:25:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'unit matching is case insensitive when selling Box inventory'
);
select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000420',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000304',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '1',
            'unit_label', 'BOX',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-22T00:26:00Z',
            'created_at', '2026-08-22T00:26:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'P0001',
    'Sale exceeds the quantity held for the selected unit',
    'sale cannot borrow stock from another unit'
);

select lives_ok(
    $$
    select * from public.mutate_investment_trade(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000421',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'channel_id', '30000000-0000-4000-8000-000000000201',
            'asset_id', '30000000-0000-4000-8000-000000000304',
            'kind_raw_value', 'sell',
            'quantity_decimal_string', '3',
            'unit_label', 'pack',
            'gross_amount_minor', 0,
            'currency_code', 'JPY',
            'accounting_gross_amount_minor', 0,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-22T00:27:00Z',
            'created_at', '2026-08-22T00:27:00Z',
            'last_modified_by_device_id', '30000000-0000-4000-8000-000000000901'
        ),
        null,
        false
    )
    $$,
    'all remaining pack inventory can be sold independently'
);
select throws_ok(
    $$
    select * from public.mutate_investment_trade(
        (
            select to_jsonb(trade) || jsonb_build_object('unit_label', 'box')
            from public.investment_trades trade
            where id = '30000000-0000-4000-8000-000000000417'
        ),
        (select sync_version from public.investment_trades where id = '30000000-0000-4000-8000-000000000417'),
        false
    )
    $$,
    'P0001',
    'Sale exceeds the quantity held for the selected unit',
    'editing a historical unit is rejected when it makes a later sale oversell'
);
select is(
    (select unit_label from public.investment_trades where id = '30000000-0000-4000-8000-000000000417'),
    'pack',
    'failed unit edit rolls back the original trade unit'
);

select lives_ok(
    $$
    select * from public.delete_investment_asset(
        '30000000-0000-4000-8000-000000000304',
        '30000000-0000-4000-8000-000000000001',
        (select sync_version from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
        '2026-08-22T00:30:00Z'::timestamptz,
        '30000000-0000-4000-8000-000000000901'
    )
    $$,
    'asset delete RPC soft-deletes a settled product while preserving FIFO history'
);
select is(
    (select deleted_at from public.investment_assets where id = '30000000-0000-4000-8000-000000000304'),
    '2026-08-22T00:30:00Z'::timestamptz,
    'settled product is marked as deleted'
);
select is(
    (
        select count(*)::integer
        from public.investment_trades
        where asset_id = '30000000-0000-4000-8000-000000000304'
          and deleted_at is null
    ),
    5,
    'soft-deleting a settled product keeps its transaction history'
);

insert into public.ledger_wallets(
    id, user_id, name, kind_raw_value, icon_symbol_name, icon_color_hex,
    currency_code, opening_balance_minor
)
values
    (
        '30000000-0000-4000-8000-000000000108',
        '30000000-0000-4000-8000-000000000001',
        'Investment card', 'creditCard', 'creditcard.fill', '#888888', 'JPY', 0
    ),
    (
        '30000000-0000-4000-8000-000000000109',
        '30000000-0000-4000-8000-000000000001',
        'USD wallet', 'cash', 'banknote.fill', '#999999', 'USD', 0
    );

select lives_ok(
    $$
    update public.ledger_wallets
    set investment_linked_wallet_id = '30000000-0000-4000-8000-000000000101'
    where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    $$,
    'owner can link an active same-currency non-card wallet'
);
select throws_ok(
    $$
    update public.ledger_wallets
    set investment_linked_wallet_id = '30000000-0000-4000-8000-000000000108'
    where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    $$,
    'P0001',
    'Invalid linked investment wallet',
    'credit cards cannot become the linked investment wallet'
);
select throws_ok(
    $$
    update public.ledger_wallets
    set investment_linked_wallet_id = '30000000-0000-4000-8000-000000000109'
    where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    $$,
    'P0001',
    'Invalid linked investment wallet',
    'linked investment wallet must use the Investment Wallet currency'
);

insert into public.family_permission_grants(
    id, family_id, grantee_user_id, owner_user_id, resource_type,
    resource_id, permission_scope, granted_by_user_id
)
values
    (
        '30000000-0000-4000-8000-000000000951',
        '30000000-0000-4000-8000-000000000010',
        '30000000-0000-4000-8000-000000000002',
        '30000000-0000-4000-8000-000000000001',
        'investment', null, 'view',
        '30000000-0000-4000-8000-000000000001'
    ),
    (
        '30000000-0000-4000-8000-000000000952',
        '30000000-0000-4000-8000-000000000010',
        '30000000-0000-4000-8000-000000000002',
        '30000000-0000-4000-8000-000000000001',
        'wallet', '30000000-0000-4000-8000-000000000103', 'use',
        '30000000-0000-4000-8000-000000000001'
    );
select pg_temp.set_actor('30000000-0000-4000-8000-000000000002');
select throws_ok(
    $$
    update public.ledger_wallets
    set investment_linked_wallet_id = '30000000-0000-4000-8000-000000000103'
    where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    $$,
    'P0001',
    'Investment edit permission is required',
    'Investment View and wallet Use do not allow changing the linked wallet without Investment Edit'
);

select pg_temp.set_actor('30000000-0000-4000-8000-000000000001');
insert into public.family_permission_grants(
    id, family_id, grantee_user_id, owner_user_id, resource_type,
    resource_id, permission_scope, granted_by_user_id
)
values (
    '30000000-0000-4000-8000-000000000953',
    '30000000-0000-4000-8000-000000000010',
    '30000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001',
    'investment', null, 'edit',
    '30000000-0000-4000-8000-000000000001'
);
select pg_temp.set_actor('30000000-0000-4000-8000-000000000002');
select lives_ok(
    $$
    update public.ledger_wallets
    set investment_linked_wallet_id = '30000000-0000-4000-8000-000000000103'
    where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    $$,
    'Investment Edit plus wallet Use allows changing the linked wallet'
);
select throws_ok(
    $$
    update public.ledger_wallets
    set investment_linked_wallet_id = '30000000-0000-4000-8000-000000000101'
    where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    $$,
    'P0001',
    'Wallet use permission is required',
    'Investment Edit cannot link a wallet without wallet Use'
);

select pg_temp.set_actor('30000000-0000-4000-8000-000000000001');
select throws_ok(
    $$
    update public.ledger_wallets
    set is_archived = true
    where id = '30000000-0000-4000-8000-000000000103'
    $$,
    'P0001',
    'Move investment cash and unlink this wallet before changing or archiving it',
    'a linked wallet cannot be archived before unlinking it'
);

select lives_ok(
    $$
    select * from public.mutate_investment_cash_posting(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000961',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'event_id', '30000000-0000-4000-8000-000000000971',
            'wallet_id', '30000000-0000-4000-8000-000000000101',
            'ledger_transaction_id', (
                select id from public.ledger_transactions
                where user_id = '30000000-0000-4000-8000-000000000001'
                  and deleted_at is null limit 1
            ),
            'role_raw_value', 'cashAccrual',
            'cash_bucket_raw_value', 'booked',
            'cash_origin_raw_value', 'manual',
            'amount_minor', 10,
            'currency_code', 'JPY',
            'accounting_amount_minor', 10,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-24T00:00:00Z',
            'created_at', '2026-08-24T00:00:00Z',
            'updated_at', '2026-08-24T00:00:00Z'
        ), null, false
    )
    $$,
    'cash mutation RPC can create an allocation under the owner advisory lock'
);
select lives_ok(
    $$
    select * from public.mutate_investment_cash_posting(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000962',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'event_id', '30000000-0000-4000-8000-000000000972',
            'wallet_id', '30000000-0000-4000-8000-000000000101',
            'ledger_transaction_id', (
                select id from public.ledger_transactions
                where user_id = '30000000-0000-4000-8000-000000000001'
                  and deleted_at is null limit 1
            ),
            'role_raw_value', 'cashConsumption',
            'cash_bucket_raw_value', 'booked',
            'cash_origin_raw_value', 'manual',
            'amount_minor', -10,
            'currency_code', 'JPY',
            'accounting_amount_minor', -10,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-24T00:01:00Z',
            'created_at', '2026-08-24T00:01:00Z',
            'updated_at', '2026-08-24T00:01:00Z'
        ), null, false
    )
    $$,
    'first device can consume the available investment cash'
);
select throws_ok(
    $$
    select * from public.mutate_investment_cash_posting(
        jsonb_build_object(
            'id', '30000000-0000-4000-8000-000000000963',
            'user_id', '30000000-0000-4000-8000-000000000001',
            'event_id', '30000000-0000-4000-8000-000000000973',
            'wallet_id', '30000000-0000-4000-8000-000000000101',
            'ledger_transaction_id', (
                select id from public.ledger_transactions
                where user_id = '30000000-0000-4000-8000-000000000001'
                  and deleted_at is null limit 1
            ),
            'role_raw_value', 'cashConsumption',
            'cash_bucket_raw_value', 'booked',
            'cash_origin_raw_value', 'manual',
            'amount_minor', -1,
            'currency_code', 'JPY',
            'accounting_amount_minor', -1,
            'accounting_currency_code', 'JPY',
            'occurred_at', '2026-08-24T00:02:00Z',
            'created_at', '2026-08-24T00:02:00Z',
            'updated_at', '2026-08-24T00:02:00Z'
        ), null, false
    )
    $$,
    'P0001',
    'Investment cash was already used on another device',
    'a second device cannot consume the same booked allocation'
);

select * from finish();

rollback;
