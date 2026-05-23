-- Family transfers are created only through this RPC so sender/recipient rows
-- and the recipient notification stay atomic.

create or replace function public.prevent_family_transfer_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if old.transfer_subtype_raw_value = 'familyTransfer' then
        raise exception 'Family transfers cannot be modified';
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

drop trigger if exists ledger_transactions_family_transfer_immutable on public.ledger_transactions;
create trigger ledger_transactions_family_transfer_immutable
before update or delete on public.ledger_transactions
for each row execute function public.prevent_family_transfer_mutation();

create or replace function public.create_family_transfer(
    p_family_id uuid,
    p_recipient_user_id uuid,
    p_source_wallet_id uuid,
    p_destination_wallet_id uuid,
    p_amount_minor bigint,
    p_occurred_at timestamptz
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
    notification_amount_text text;
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

    select *
    into source_wallet
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

    select *
    into destination_wallet
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

    sender_note := 'Chuyển đến ví ' || destination_wallet.name || ' của ' || recipient_name;
    recipient_note := 'Nhận từ ví ' || source_wallet.name || ' của ' || actor_name;
    notification_amount_text := p_amount_minor::text || ' ' || coalesce(nullif(source_wallet.currency_code, ''), 'JPY');

    insert into public.ledger_transactions (
        id,
        user_id,
        primary_kind_raw_value,
        transfer_subtype_raw_value,
        debt_intent_raw_value,
        entry_status_raw_value,
        title,
        note,
        amount_minor,
        occurred_at,
        counterparty_name,
        normalized_counterparty_key,
        source_wallet_id,
        destination_wallet_id,
        category_id,
        created_at,
        updated_at,
        deleted_at,
        created_by_user_id,
        last_modified_by_user_id,
        is_archived,
        archived_at
    )
    values (
        sender_transaction_id,
        actor_id,
        'transfer',
        'familyTransfer',
        null,
        'posted',
        'Chuyển tiền gia đình',
        sender_note,
        p_amount_minor,
        p_occurred_at,
        recipient_name,
        null,
        p_source_wallet_id,
        p_destination_wallet_id,
        null,
        created_time,
        created_time,
        null,
        actor_id,
        actor_id,
        false,
        null
    )
    returning * into sender_transaction_row;

    insert into public.ledger_transactions (
        id,
        user_id,
        primary_kind_raw_value,
        transfer_subtype_raw_value,
        debt_intent_raw_value,
        entry_status_raw_value,
        title,
        note,
        amount_minor,
        occurred_at,
        counterparty_name,
        normalized_counterparty_key,
        source_wallet_id,
        destination_wallet_id,
        category_id,
        created_at,
        updated_at,
        deleted_at,
        created_by_user_id,
        last_modified_by_user_id,
        is_archived,
        archived_at
    )
    values (
        recipient_transaction_id,
        p_recipient_user_id,
        'transfer',
        'familyTransfer',
        null,
        'posted',
        'Nhận tiền gia đình',
        recipient_note,
        p_amount_minor,
        p_occurred_at,
        actor_name,
        null,
        p_destination_wallet_id,
        null,
        null,
        created_time,
        created_time,
        null,
        actor_id,
        actor_id,
        false,
        null
    )
    returning * into recipient_transaction_row;

    insert into public.family_notifications (
        source_event_key,
        family_id,
        user_id,
        actor_user_id,
        kind,
        resource_type,
        resource_id,
        permission_scope,
        permission_request_id,
        action_state,
        title,
        body,
        metadata,
        read_at,
        created_at,
        updated_at
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
        actor_name || ' đã chuyển ' || notification_amount_text || ' đến ví ' || destination_wallet.name || ' của bạn.',
        jsonb_build_object(
            'action', 'family_transfer',
            'sender_transaction_id', sender_transaction_id,
            'recipient_transaction_id', recipient_transaction_id,
            'source_wallet_id', p_source_wallet_id,
            'destination_wallet_id', p_destination_wallet_id,
            'amount_minor', p_amount_minor
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

grant execute on function public.create_family_transfer(uuid, uuid, uuid, uuid, bigint, timestamptz) to authenticated;
