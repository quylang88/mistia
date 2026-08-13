begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
    '40000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
    'family-transfer-balance@mistia.test', '', timezone('utc'::text, now()),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    timezone('utc'::text, now()), timezone('utc'::text, now())
)
on conflict (id) do nothing;

insert into public.ledger_wallets (
    id, user_id, name, kind_raw_value, icon_symbol_name, icon_color_hex,
    currency_code, opening_balance_minor
)
values
    (
        '40000000-0000-4000-8000-000000000101',
        '40000000-0000-4000-8000-000000000001',
        'Family transfer wallet', 'cash', 'banknote.fill', '#111111', 'JPY', 100
    ),
    (
        '40000000-0000-4000-8000-000000000102',
        '40000000-0000-4000-8000-000000000001',
        'Remote family wallet', 'cash', 'banknote.fill', '#222222', 'JPY', 0
    );

insert into public.ledger_transactions (
    id, user_id, primary_kind_raw_value, transfer_subtype_raw_value,
    entry_status_raw_value, title, amount_minor, occurred_at,
    source_wallet_id, destination_wallet_id,
    created_by_user_id, last_modified_by_user_id
)
values
    (
        '40000000-0000-4000-8000-000000000201',
        '40000000-0000-4000-8000-000000000001',
        'transfer', 'familyTransfer', 'posted', 'Family transfer received', 500,
        timezone('utc'::text, now()),
        '40000000-0000-4000-8000-000000000101', null,
        '40000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000001'
    ),
    (
        '40000000-0000-4000-8000-000000000202',
        '40000000-0000-4000-8000-000000000001',
        'transfer', 'familyTransfer', 'posted', 'Family transfer sent', 120,
        timezone('utc'::text, now()),
        '40000000-0000-4000-8000-000000000101',
        '40000000-0000-4000-8000-000000000102',
        '40000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000001'
    );

select is(
    public.mistia_calculate_wallet_current_balance(
        '40000000-0000-4000-8000-000000000101',
        '40000000-0000-4000-8000-000000000001',
        'cash',
        100
    ),
    480::bigint,
    'family transfers apply received money as income and sent money as expense'
);

select is(
    (select current_balance_minor from public.ledger_wallets where id = '40000000-0000-4000-8000-000000000101'),
    480::bigint,
    'the source wallet snapshot follows family-transfer direction'
);

select is(
    public.mistia_calculate_wallet_current_balance(
        '40000000-0000-4000-8000-000000000102',
        '40000000-0000-4000-8000-000000000001',
        'cash',
        0
    ),
    0::bigint,
    'a family-transfer destination marker is not counted as a local wallet deposit'
);

select is(
    (select current_balance_minor from public.ledger_wallets where id = '40000000-0000-4000-8000-000000000102'),
    0::bigint,
    'the destination marker wallet snapshot remains unchanged'
);

select * from finish();

rollback;
