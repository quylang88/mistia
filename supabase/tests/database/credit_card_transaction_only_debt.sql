begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

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
values (
    '20000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'credit-card-transaction-only@mistia.test',
    '',
    timezone('utc'::text, now()),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
)
on conflict (id) do nothing;

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
values
    (
        '20000000-0000-4000-8000-000000000101',
        '20000000-0000-4000-8000-000000000001',
        'Member credit card',
        'creditCard',
        'creditcard.fill',
        '#7C3AED',
        'JPY',
        46058
    ),
    (
        '20000000-0000-4000-8000-000000000102',
        '20000000-0000-4000-8000-000000000001',
        'Member bank',
        'bank',
        'building.columns.fill',
        '#2563EB',
        'JPY',
        46058
    );

insert into public.credit_card_profiles (
    id,
    user_id,
    issuer_name,
    network_raw_value,
    last4,
    credit_limit_minor,
    statement_closing_day,
    payment_due_day,
    wallet_id
)
values (
    '20000000-0000-4000-8000-000000000201',
    '20000000-0000-4000-8000-000000000001',
    'Test Issuer',
    'visa',
    '1234',
    350000,
    10,
    26,
    '20000000-0000-4000-8000-000000000101'
);

insert into public.ledger_transactions (
    id,
    user_id,
    primary_kind_raw_value,
    entry_status_raw_value,
    title,
    amount_minor,
    occurred_at,
    source_wallet_id,
    created_by_user_id,
    last_modified_by_user_id
)
values (
    '20000000-0000-4000-8000-000000000301',
    '20000000-0000-4000-8000-000000000001',
    'expense',
    'posted',
    'Real card purchase',
    25916,
    timezone('utc'::text, now()),
    '20000000-0000-4000-8000-000000000101',
    '20000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001'
);

select is(
    public.mistia_calculate_wallet_current_balance(
        '20000000-0000-4000-8000-000000000101',
        '20000000-0000-4000-8000-000000000001',
        'creditCard',
        46058
    ),
    324084::bigint,
    'credit-card available credit uses only real transaction debt'
);

select is(
    (
        select current_balance_minor
        from public.ledger_wallets
        where id = '20000000-0000-4000-8000-000000000101'
    ),
    324084::bigint,
    'persisted credit-card balance ignores stored opening debt'
);

select is(
    (
        select opening_balance_minor
        from public.ledger_wallets
        where id = '20000000-0000-4000-8000-000000000101'
    ),
    46058::bigint,
    'existing credit-card opening field is not rewritten'
);

select is(
    (
        select current_balance_minor
        from public.ledger_wallets
        where id = '20000000-0000-4000-8000-000000000102'
    ),
    46058::bigint,
    'non-card wallets keep their opening balance'
);

select * from finish();

rollback;
