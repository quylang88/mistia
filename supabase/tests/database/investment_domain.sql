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
    120::bigint,
    'old capital-return wallet is restored after moving the sale'
);
select is(
    (select current_balance_minor from public.ledger_wallets where id = '30000000-0000-4000-8000-000000000105'),
    150::bigint,
    'new capital-return wallet receives the released cost basis'
);
select is(
    (
        select current_balance_minor from public.ledger_wallets
        where id = public.investment_system_wallet_id('30000000-0000-4000-8000-000000000001')
    ),
    140::bigint,
    'Investment Wallet reflects profit after moving the sale'
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
    'Sale exceeds the quantity held',
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
    150::bigint,
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
    30::bigint,
    'deleting the sale restores Investment Wallet profit'
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
