-- Add nullable multi-currency transaction fields and update family transfer creation.

alter table public.ledger_transactions
    add column if not exists source_currency_code text,
    add column if not exists destination_currency_code text,
    add column if not exists destination_amount_minor bigint,
    add column if not exists reporting_currency_code text,
    add column if not exists reporting_amount_minor bigint,
    add column if not exists conversion_mode_raw_value text,
    add column if not exists exchange_rate_decimal_string text,
    add column if not exists exchange_rate_provider text,
    add column if not exists exchange_rate_date text;

drop function if exists public.create_family_transfer(uuid, uuid, uuid, uuid, bigint, timestamptz, text);

create or replace function public.create_family_transfer(
    p_family_id uuid,
    p_recipient_user_id uuid,
    p_source_wallet_id uuid,
    p_destination_wallet_id uuid,
    p_amount_minor bigint,
    p_destination_amount_minor bigint default null,
    p_conversion_mode_raw_value text default null,
    p_exchange_rate_decimal_string text default null,
    p_exchange_rate_provider text default null,
    p_exchange_rate_date text default null,
    p_occurred_at timestamptz default timezone('utc'::text, now()),
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    source_wallet public.ledger_wallets%rowtype;
    destination_wallet public.ledger_wallets%rowtype;
    actor_name text;
    recipient_name text;
    created_time timestamptz := timezone('utc'::text, now());
    sender_transaction_id uuid := gen_random_uuid();
    recipient_transaction_id uuid := gen_random_uuid();
    sender_note text;
    recipient_note text;
    source_amount_text text;
    destination_amount_text text;
    resolved_destination_amount_minor bigint;
    sender_transaction_row public.ledger_transactions%rowtype;
    recipient_transaction_row public.ledger_transactions%rowtype;
begin
    if actor_id is null then
        raise exception 'Not authenticated';
    end if;

    if actor_id = p_recipient_user_id then
        raise exception 'Cannot transfer to yourself through family transfer';
    end if;

    if p_amount_minor <= 0 then
        raise exception 'Transfer amount must be positive';
    end if;

    if public.shared_active_family_id(actor_id, p_recipient_user_id) is distinct from p_family_id then
        raise exception 'Both users must be active members of this family';
    end if;

    select * into source_wallet
    from public.ledger_wallets
    where id = p_source_wallet_id
    for share;

    if source_wallet.id is null then
        raise exception 'Source wallet not found';
    end if;

    if source_wallet.user_id <> actor_id then
        raise exception 'Source wallet must belong to the sender';
    end if;

    if source_wallet.deleted_at is not null or source_wallet.is_archived then
        raise exception 'Source wallet is not active';
    end if;

    if source_wallet.kind_raw_value = 'creditCard' then
        raise exception 'Credit cards cannot send family transfers';
    end if;

    select * into destination_wallet
    from public.ledger_wallets
    where id = p_destination_wallet_id
    for share;

    if destination_wallet.id is null then
        raise exception 'Destination wallet not found';
    end if;

    if destination_wallet.user_id <> p_recipient_user_id then
        raise exception 'Destination wallet must belong to the recipient';
    end if;

    if destination_wallet.deleted_at is not null or destination_wallet.is_archived then
        raise exception 'Destination wallet is not active';
    end if;

    if not public.can_operate_wallet(p_destination_wallet_id) then
        raise exception 'Sender does not have permission to use the destination wallet';
    end if;

    resolved_destination_amount_minor := coalesce(p_destination_amount_minor, p_amount_minor);
    if resolved_destination_amount_minor <= 0 then
        raise exception 'Destination amount must be positive';
    end if;

    select coalesce(nullif(trim(display_name), ''), 'Thành viên')
    into actor_name
    from public.user_profiles
    where user_id = actor_id;
    actor_name := coalesce(actor_name, 'Thành viên');

    select coalesce(nullif(trim(display_name), ''), 'Thành viên')
    into recipient_name
    from public.user_profiles
    where user_id = p_recipient_user_id;
    recipient_name := coalesce(recipient_name, 'Thành viên');

    if p_note is not null and trim(p_note) <> '' then
        sender_note := trim(p_note);
        recipient_note := trim(p_note);
    else
        sender_note := null;
        recipient_note := null;
    end if;

    source_amount_text := p_amount_minor::text || ' ' || coalesce(nullif(source_wallet.currency_code, ''), 'JPY');
    destination_amount_text := resolved_destination_amount_minor::text || ' ' || coalesce(nullif(destination_wallet.currency_code, ''), 'JPY');

    insert into public.ledger_transactions (
        id, user_id, primary_kind_raw_value, transfer_subtype_raw_value, debt_intent_raw_value,
        entry_status_raw_value, title, note, amount_minor,
        source_currency_code, destination_currency_code, destination_amount_minor,
        conversion_mode_raw_value, exchange_rate_decimal_string, exchange_rate_provider, exchange_rate_date,
        occurred_at, counterparty_name, normalized_counterparty_key,
        source_wallet_id, destination_wallet_id, category_id,
        created_at, updated_at, deleted_at, created_by_user_id, last_modified_by_user_id,
        is_archived, archived_at
    )
    values (
        sender_transaction_id, actor_id, 'transfer', 'familyTransfer', null,
        'posted', 'Chuyển tiền gia đình', sender_note, p_amount_minor,
        source_wallet.currency_code, destination_wallet.currency_code, resolved_destination_amount_minor,
        p_conversion_mode_raw_value, p_exchange_rate_decimal_string, p_exchange_rate_provider, p_exchange_rate_date,
        p_occurred_at, recipient_name, null,
        p_source_wallet_id, p_destination_wallet_id, null,
        created_time, created_time, null, actor_id, actor_id,
        false, null
    )
    returning * into sender_transaction_row;

    insert into public.ledger_transactions (
        id, user_id, primary_kind_raw_value, transfer_subtype_raw_value, debt_intent_raw_value,
        entry_status_raw_value, title, note, amount_minor,
        source_currency_code, destination_currency_code, destination_amount_minor,
        conversion_mode_raw_value, exchange_rate_decimal_string, exchange_rate_provider, exchange_rate_date,
        occurred_at, counterparty_name, normalized_counterparty_key,
        source_wallet_id, destination_wallet_id, category_id,
        created_at, updated_at, deleted_at, created_by_user_id, last_modified_by_user_id,
        is_archived, archived_at
    )
    values (
        recipient_transaction_id, p_recipient_user_id, 'transfer', 'familyTransfer', null,
        'posted', 'Nhận tiền gia đình', recipient_note, resolved_destination_amount_minor,
        destination_wallet.currency_code, null, null,
        p_conversion_mode_raw_value, p_exchange_rate_decimal_string, p_exchange_rate_provider, p_exchange_rate_date,
        p_occurred_at, actor_name, null,
        p_destination_wallet_id, null, null,
        created_time, created_time, null, actor_id, actor_id,
        false, null
    )
    returning * into recipient_transaction_row;

    insert into public.family_notifications (
        source_event_key, family_id, user_id, actor_user_id, kind, resource_type, resource_id,
        permission_scope, permission_request_id, action_state, title, body, metadata,
        read_at, created_at, updated_at
    )
    values (
        'family-transfer:' || recipient_transaction_id::text,
        p_family_id,
        p_recipient_user_id,
        actor_id,
        'family_activity',
        'transaction',
        recipient_transaction_id,
        null,
        null,
        'informational',
        'Nhận tiền',
        actor_name || ' đã chuyển ' || source_amount_text || ' đến ví ' || destination_wallet.name || ' của bạn (' || destination_amount_text || ').',
        jsonb_build_object(
            'action', 'family_transfer',
            'sender_transaction_id', sender_transaction_id::text,
            'recipient_transaction_id', recipient_transaction_id::text,
            'source_wallet_id', p_source_wallet_id::text,
            'destination_wallet_id', p_destination_wallet_id::text,
            'amount_minor', p_amount_minor::text,
            'destination_amount_minor', resolved_destination_amount_minor::text,
            'source_currency_code', source_wallet.currency_code,
            'destination_currency_code', destination_wallet.currency_code
        ),
        null,
        created_time,
        created_time
    );

    return jsonb_build_object(
        'sender_transaction', to_jsonb(sender_transaction_row),
        'recipient_transaction', to_jsonb(recipient_transaction_row)
    );
end;
$$;

grant execute on function public.create_family_transfer(
    uuid, uuid, uuid, uuid, bigint, bigint, text, text, text, text, timestamptz, text
) to authenticated;
