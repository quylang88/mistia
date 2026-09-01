-- Two-way Investment Wallet cash reclassification. The ledger transaction and
-- its deterministic cash-allocation posting are mutated under one owner lock,
-- so another device cannot over-refill or over-withdraw between separate RPCs.

create index if not exists investment_wallet_postings_owner_cash_history_idx
    on public.investment_wallet_postings(user_id, occurred_at desc, event_id)
    where deleted_at is null and cash_bucket_raw_value is not null;

create or replace function public.mutate_investment_cash_event(
    p_transaction jsonb default null,
    p_postings jsonb default '[]'::jsonb,
    p_expected_version bigint default null,
    p_expected_posting_versions jsonb default '{}'::jsonb,
    p_force boolean default false,
    p_transaction_id uuid default null,
    p_owner_user_id uuid default null,
    p_deleted_at timestamptz default null,
    p_device_id uuid default null
)
returns setof public.ledger_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    incoming public.ledger_transactions%rowtype;
    existing public.ledger_transactions%rowtype;
    saved public.ledger_transactions%rowtype;
    system_wallet public.ledger_wallets%rowtype;
    linked_wallet public.ledger_wallets%rowtype;
    selected_wallet public.ledger_wallets%rowtype;
    existing_posting public.investment_wallet_postings%rowtype;
    transaction_id_value uuid;
    owner_id uuid;
    direction text;
    posting_id uuid;
    accounting_delta bigint;
    realized_profit bigint;
    available_without_event bigint;
    linked_without_event bigint;
    source_investment_without_event bigint;
    source_actual_without_event bigint;
    maximum_amount bigint;
    next_version bigint;
    mutation_time timestamptz;
    is_deleting boolean := false;
    supplied_posting jsonb;
    expected_posting_version bigint;
begin
    if actor_id is null then
        raise exception 'investment_cash_authentication_required';
    end if;
    if p_transaction is not null then
        select * into incoming
        from jsonb_populate_record(null::public.ledger_transactions, p_transaction);
        transaction_id_value := incoming.id;
        owner_id := incoming.user_id;
        is_deleting := incoming.deleted_at is not null;
    else
        transaction_id_value := p_transaction_id;
        owner_id := p_owner_user_id;
        is_deleting := p_deleted_at is not null;
    end if;
    if transaction_id_value is null or owner_id is null then
        raise exception 'investment_cash_invalid_event';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':investment-cash', 0));
    select * into existing
    from public.ledger_transactions
    where id = transaction_id_value and user_id = owner_id
    for update;

    if existing.id is null then
        if is_deleting then return; end if;
        if not public.has_investment_permission(owner_id, 'create') then
            raise exception 'investment_cash_create_permission_required';
        end if;
        if not p_force and p_expected_version is not null and p_expected_version <> 0 then
            return;
        end if;
    else
        if not public.has_investment_permission(owner_id, 'edit') then
            raise exception 'investment_cash_edit_permission_required';
        end if;
        if not p_force and (
            p_expected_version is null
            or existing.sync_version <> p_expected_version
        ) then
            return;
        end if;
    end if;

    direction := case
        when coalesce(incoming.settlement_role_raw_value, existing.settlement_role_raw_value)
            = 'investmentCashDeposit' then 'deposit'
        when coalesce(incoming.settlement_role_raw_value, existing.settlement_role_raw_value)
            = 'investmentCashWithdrawal' then 'withdrawal'
        else null
    end;
    if direction is null then
        raise exception 'investment_cash_invalid_direction';
    end if;
    if existing.id is not null
       and existing.settlement_role_raw_value is distinct from incoming.settlement_role_raw_value
       and not is_deleting then
        raise exception 'investment_cash_direction_locked';
    end if;

    select * into system_wallet
    from public.ledger_wallets
    where id = public.investment_system_wallet_id(owner_id)
      and user_id = owner_id
      and system_purpose_raw_value = 'investmentProfit'
      and deleted_at is null
    for share;
    if system_wallet.id is null or system_wallet.investment_linked_wallet_id is null then
        raise exception 'investment_cash_linked_wallet_required';
    end if;
    select * into linked_wallet
    from public.ledger_wallets
    where id = system_wallet.investment_linked_wallet_id
      and user_id = owner_id
      and system_purpose_raw_value is null
      and kind_raw_value <> 'creditCard'
      and deleted_at is null
      and not is_archived
    for update;
    if linked_wallet.id is null
       or upper(linked_wallet.currency_code) <> upper(system_wallet.currency_code) then
        raise exception 'investment_cash_invalid_linked_wallet';
    end if;

    posting_id := public.investment_ledger_id(transaction_id_value, 'cash-transfer-posting');
    select * into existing_posting
    from public.investment_wallet_postings
    where id = posting_id
    for update;
    if p_expected_posting_versions ? lower(posting_id::text) then
        expected_posting_version := (p_expected_posting_versions->>lower(posting_id::text))::bigint;
        if existing_posting.id is null
           or (not p_force and existing_posting.sync_version <> expected_posting_version) then
            return;
        end if;
    end if;

    select coalesce(sum(realized_profit_loss_minor), 0) into realized_profit
    from public.investment_trades
    where user_id = owner_id and deleted_at is null;
    select coalesce(sum(accounting_amount_minor), 0) into available_without_event
    from public.investment_wallet_postings
    where user_id = owner_id
      and deleted_at is null
      and cash_bucket_raw_value is not null
      and id <> posting_id;
    select coalesce(sum(accounting_amount_minor), 0) into linked_without_event
    from public.investment_wallet_postings
    where user_id = owner_id
      and wallet_id = linked_wallet.id
      and deleted_at is null
      and cash_bucket_raw_value = 'booked'
      and id <> posting_id;

    if is_deleting then
        if existing.id is null or existing.deleted_at is not null then return; end if;
        if direction = 'deposit'
           and (available_without_event < 0 or linked_without_event < 0) then
            raise exception 'investment_cash_has_dependent_events';
        end if;
        if direction = 'withdrawal'
           and available_without_event > greatest(realized_profit, 0) then
            raise exception 'investment_cash_has_dependent_events';
        end if;
        mutation_time := coalesce(p_deleted_at, incoming.deleted_at, timezone('utc'::text, now()));
        update public.investment_wallet_postings
        set deleted_at = mutation_time,
            updated_at = mutation_time,
            sync_version = sync_version + 1,
            last_modified_by_device_id = coalesce(p_device_id, incoming.last_modified_by_device_id)
        where user_id = owner_id
          and event_id = transaction_id_value
          and deleted_at is null;
        update public.ledger_transactions
        set deleted_at = mutation_time,
            updated_at = mutation_time,
            sync_version = sync_version + 1,
            last_modified_by_device_id = coalesce(p_device_id, incoming.last_modified_by_device_id),
            last_modified_by_user_id = actor_id
        where id = transaction_id_value
        returning * into saved;
        return next saved;
        return;
    end if;

    if incoming.id is null
       or incoming.user_id is distinct from owner_id
       or incoming.primary_kind_raw_value <> 'transfer'
       or incoming.transfer_subtype_raw_value <> 'internalTransfer'
       or incoming.entry_status_raw_value <> 'posted'
       or incoming.amount_minor <= 0
       or incoming.destination_amount_minor is distinct from incoming.amount_minor
       or incoming.reporting_amount_minor is distinct from incoming.amount_minor
       or incoming.category_id is not null
       or coalesce(incoming.reporting_expense_minor, 0) <> 0
       or coalesce(incoming.reporting_income_minor, 0) <> 0
       or coalesce(incoming.is_archived, false)
       or incoming.deleted_at is not null then
        raise exception 'investment_cash_invalid_event';
    end if;

    if direction = 'deposit' then
        if incoming.destination_wallet_id is distinct from linked_wallet.id then
            raise exception 'investment_cash_invalid_destination';
        end if;
        select * into selected_wallet
        from public.ledger_wallets
        where id = incoming.source_wallet_id and user_id = owner_id
        for update;
        accounting_delta := incoming.amount_minor;
    else
        if incoming.source_wallet_id is distinct from linked_wallet.id then
            raise exception 'investment_cash_invalid_source';
        end if;
        select * into selected_wallet
        from public.ledger_wallets
        where id = incoming.destination_wallet_id and user_id = owner_id
        for update;
        accounting_delta := -incoming.amount_minor;
    end if;
    if selected_wallet.id is null
       or selected_wallet.system_purpose_raw_value is not null
       or selected_wallet.kind_raw_value in ('creditCard', 'investment')
       or selected_wallet.deleted_at is not null
       or selected_wallet.is_archived
       or upper(selected_wallet.currency_code) <> upper(linked_wallet.currency_code)
       or upper(coalesce(incoming.source_currency_code, '')) <> upper(linked_wallet.currency_code)
       or upper(coalesce(incoming.destination_currency_code, '')) <> upper(linked_wallet.currency_code)
       or upper(coalesce(incoming.reporting_currency_code, '')) <> upper(linked_wallet.currency_code)
       or not public.can_operate_wallet(linked_wallet.id)
       or not public.can_operate_wallet(selected_wallet.id) then
        raise exception 'investment_cash_invalid_wallet';
    end if;

    if jsonb_typeof(coalesce(p_postings, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_postings, '[]'::jsonb)) > 1 then
        raise exception 'investment_cash_invalid_postings';
    end if;
    if jsonb_array_length(coalesce(p_postings, '[]'::jsonb)) = 1 then
        supplied_posting := p_postings->0;
        if (supplied_posting->>'id')::uuid is distinct from posting_id
           or (supplied_posting->>'event_id')::uuid is distinct from transaction_id_value
           or (supplied_posting->>'wallet_id')::uuid is distinct from linked_wallet.id
           or coalesce(supplied_posting->>'role_raw_value', '') <> 'cashTransfer'
           or coalesce(supplied_posting->>'cash_bucket_raw_value', '') <> 'booked'
           or (supplied_posting->>'accounting_amount_minor')::bigint is distinct from accounting_delta then
            raise exception 'investment_cash_invalid_postings';
        end if;
    end if;

    if direction = 'deposit' then
        select coalesce(sum(accounting_amount_minor), 0) into source_investment_without_event
        from public.investment_wallet_postings
        where user_id = owner_id
          and wallet_id = selected_wallet.id
          and deleted_at is null
          and cash_bucket_raw_value is not null
          and id <> posting_id;
        source_actual_without_event := selected_wallet.current_balance_minor;
        if existing.id is not null and existing.deleted_at is null then
            if existing.source_wallet_id = selected_wallet.id then
                source_actual_without_event := source_actual_without_event + existing.amount_minor;
            end if;
            if existing.destination_wallet_id = selected_wallet.id then
                source_actual_without_event := source_actual_without_event
                    - coalesce(existing.destination_amount_minor, existing.amount_minor);
            end if;
        end if;
        maximum_amount := least(
            greatest(
                greatest(realized_profit, 0) - greatest(available_without_event, 0),
                0
            ),
            greatest(
                source_actual_without_event - greatest(source_investment_without_event, 0),
                0
            )
        );
    else
        maximum_amount := greatest(linked_without_event, 0);
    end if;
    if incoming.amount_minor > maximum_amount
       or available_without_event + accounting_delta < 0
       or available_without_event + accounting_delta > greatest(realized_profit, 0)
       or linked_without_event + accounting_delta < 0 then
        raise exception 'investment_cash_limit_conflict';
    end if;

    next_version := case when existing.id is null then 1 else existing.sync_version + 1 end;
    mutation_time := coalesce(incoming.updated_at, timezone('utc'::text, now()));
    insert into public.ledger_transactions (
        id, user_id, primary_kind_raw_value, transfer_subtype_raw_value,
        debt_intent_raw_value, entry_status_raw_value, title, note, amount_minor,
        source_currency_code, destination_currency_code, destination_amount_minor,
        reporting_currency_code, reporting_amount_minor, conversion_mode_raw_value,
        exchange_rate_decimal_string, exchange_rate_provider, exchange_rate_date,
        occurred_at, created_by_user_id, last_modified_by_user_id, counterparty_name,
        normalized_counterparty_key, settlement_group_id, settlement_obligation_id,
        settlement_role_raw_value, reporting_expense_minor, reporting_income_minor,
        source_wallet_id, destination_wallet_id, category_id, deleted_at, is_archived,
        archived_at, created_at, updated_at, sync_version, last_modified_by_device_id
    ) values (
        incoming.id, owner_id, 'transfer', 'internalTransfer', null, 'posted',
        incoming.title, incoming.note, incoming.amount_minor,
        linked_wallet.currency_code, linked_wallet.currency_code, incoming.amount_minor,
        linked_wallet.currency_code, incoming.amount_minor, null, null, null, null,
        incoming.occurred_at, actor_id, actor_id, null, null, null, null,
        incoming.settlement_role_raw_value, 0, 0, incoming.source_wallet_id,
        incoming.destination_wallet_id, null, null, false, null,
        coalesce(incoming.created_at, mutation_time), mutation_time, next_version,
        incoming.last_modified_by_device_id
    ) on conflict (id) do update set
        title = excluded.title,
        note = excluded.note,
        amount_minor = excluded.amount_minor,
        source_currency_code = excluded.source_currency_code,
        destination_currency_code = excluded.destination_currency_code,
        destination_amount_minor = excluded.destination_amount_minor,
        reporting_currency_code = excluded.reporting_currency_code,
        reporting_amount_minor = excluded.reporting_amount_minor,
        occurred_at = excluded.occurred_at,
        last_modified_by_user_id = actor_id,
        settlement_role_raw_value = excluded.settlement_role_raw_value,
        source_wallet_id = excluded.source_wallet_id,
        destination_wallet_id = excluded.destination_wallet_id,
        deleted_at = null,
        is_archived = false,
        archived_at = null,
        updated_at = mutation_time,
        sync_version = next_version,
        last_modified_by_device_id = excluded.last_modified_by_device_id
    returning * into saved;

    insert into public.investment_wallet_postings (
        id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
        role_raw_value, cash_bucket_raw_value, cash_origin_raw_value,
        amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
        occurred_at, created_at, updated_at, deleted_at, sync_version,
        last_modified_by_device_id
    ) values (
        posting_id, owner_id, transaction_id_value, null, null, linked_wallet.id,
        transaction_id_value, 'cashTransfer', 'booked', 'manual', accounting_delta,
        linked_wallet.currency_code, accounting_delta, linked_wallet.currency_code,
        incoming.occurred_at, coalesce(incoming.created_at, mutation_time), mutation_time,
        null, case when existing_posting.id is null then 1 else existing_posting.sync_version + 1 end,
        incoming.last_modified_by_device_id
    ) on conflict (id) do update set
        wallet_id = excluded.wallet_id,
        ledger_transaction_id = excluded.ledger_transaction_id,
        role_raw_value = excluded.role_raw_value,
        cash_bucket_raw_value = excluded.cash_bucket_raw_value,
        cash_origin_raw_value = excluded.cash_origin_raw_value,
        amount_minor = excluded.amount_minor,
        currency_code = excluded.currency_code,
        accounting_amount_minor = excluded.accounting_amount_minor,
        accounting_currency_code = excluded.accounting_currency_code,
        occurred_at = excluded.occurred_at,
        updated_at = excluded.updated_at,
        deleted_at = null,
        sync_version = public.investment_wallet_postings.sync_version + 1,
        last_modified_by_device_id = excluded.last_modified_by_device_id;

    return next saved;
    return;
end;
$$;

revoke execute on function public.mutate_investment_cash_event(
    jsonb, jsonb, bigint, jsonb, boolean, uuid, uuid, timestamptz, uuid
) from public, anon;
grant execute on function public.mutate_investment_cash_event(
    jsonb, jsonb, bigint, jsonb, boolean, uuid, uuid, timestamptz, uuid
) to authenticated;

-- A zero-price liquidation has no receiving wallet, but its realized loss still
-- reduces the amount of earned profit that remains available. Keep that
-- allocation on the Investment system wallet so real-wallet balances stay
-- untouched while cash history records the liquidation as money out.
create or replace function public.sync_investment_cash_accrual()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    trade_row public.investment_trades%rowtype;
    target_wallet public.ledger_wallets%rowtype;
    cash_posting_id uuid;
    target_amount_minor bigint;
begin
    if new.role_raw_value <> 'realizedProfit' then
        return null;
    end if;

    select * into trade_row
    from public.investment_trades
    where id = new.trade_id;
    if trade_row.id is null then return null; end if;

    if trade_row.capital_return_wallet_id is null then
        select * into target_wallet
        from public.ledger_wallets
        where id = public.investment_system_wallet_id(new.user_id)
          and user_id = new.user_id
          and system_purpose_raw_value = 'investmentProfit'
          and deleted_at is null;
        target_amount_minor := new.accounting_amount_minor;
    else
        select * into target_wallet
        from public.ledger_wallets
        where id = trade_row.capital_return_wallet_id;
        target_amount_minor := case
            when upper(target_wallet.currency_code) = upper(new.accounting_currency_code)
                then new.accounting_amount_minor
            when coalesce(trade_row.accounting_to_capital_return_rate_decimal_string, '') <> ''
                then round(
                    trade_row.accounting_gross_amount_minor::numeric
                    * trade_row.accounting_to_capital_return_rate_decimal_string::numeric
                )::bigint - coalesce(trade_row.capital_return_wallet_amount_minor, 0)
            else new.accounting_amount_minor
        end;
    end if;
    if target_wallet.id is null then return null; end if;

    cash_posting_id := public.investment_ledger_id(new.event_id, 'cash-accrual-posting');
    update public.ledger_transactions
    set source_wallet_id = target_wallet.id,
        source_currency_code = target_wallet.currency_code,
        amount_minor = abs(target_amount_minor),
        updated_at = new.updated_at,
        sync_version = sync_version + 1
    where id = new.ledger_transaction_id
      and (source_wallet_id is distinct from target_wallet.id
        or source_currency_code is distinct from target_wallet.currency_code
        or amount_minor is distinct from abs(target_amount_minor));

    update public.investment_wallet_postings
    set wallet_id = target_wallet.id,
        amount_minor = target_amount_minor,
        currency_code = target_wallet.currency_code,
        updated_at = new.updated_at,
        sync_version = sync_version + 1
    where id = new.id
      and (wallet_id is distinct from target_wallet.id
        or amount_minor is distinct from target_amount_minor
        or currency_code is distinct from target_wallet.currency_code);

    insert into public.investment_wallet_postings (
        id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
        role_raw_value, cash_bucket_raw_value, cash_origin_raw_value,
        amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
        occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id
    ) values (
        cash_posting_id, new.user_id, new.event_id, new.trade_id, new.asset_id,
        target_wallet.id, new.ledger_transaction_id, 'cashAccrual', 'booked', 'derived',
        target_amount_minor, target_wallet.currency_code,
        new.accounting_amount_minor, new.accounting_currency_code,
        new.occurred_at, new.created_at, new.updated_at, new.deleted_at, 1,
        new.last_modified_by_device_id
    ) on conflict (id) do update set
        wallet_id = excluded.wallet_id,
        ledger_transaction_id = excluded.ledger_transaction_id,
        cash_bucket_raw_value = excluded.cash_bucket_raw_value,
        cash_origin_raw_value = excluded.cash_origin_raw_value,
        amount_minor = excluded.amount_minor,
        currency_code = excluded.currency_code,
        accounting_amount_minor = excluded.accounting_amount_minor,
        accounting_currency_code = excluded.accounting_currency_code,
        occurred_at = excluded.occurred_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        sync_version = public.investment_wallet_postings.sync_version + 1,
        last_modified_by_device_id = excluded.last_modified_by_device_id;
    return null;
end;
$$;

revoke execute on function public.sync_investment_cash_accrual() from public, anon, authenticated;

-- Re-run the trigger once for active legacy liquidations that predate this fix.
update public.investment_wallet_postings as posting
set updated_at = posting.updated_at
from public.investment_trades as trade
where posting.trade_id = trade.id
  and posting.role_raw_value = 'realizedProfit'
  and posting.accounting_amount_minor < 0
  and posting.deleted_at is null
  and trade.deleted_at is null
  and trade.capital_return_wallet_id is null;
