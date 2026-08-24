-- Keep each real wallet balance equal to its real cash while separately tracking
-- how much realized investment profit is still held by that wallet.

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
    select * into trade_row from public.investment_trades where id = new.trade_id;
    if trade_row.id is null or trade_row.capital_return_wallet_id is null then return null; end if;
    select * into target_wallet from public.ledger_wallets where id = trade_row.capital_return_wallet_id;
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
        new.occurred_at, new.created_at, new.updated_at, new.deleted_at, 1, new.last_modified_by_device_id
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

create or replace function public.mutate_investment_cash_posting(
    p_row jsonb,
    p_expected_version bigint default null,
    p_force boolean default false
)
returns public.investment_wallet_postings
language plpgsql
security definer
set search_path = public
as $$
declare
    owner_id uuid := (p_row->>'user_id')::uuid;
    posting_id uuid := (p_row->>'id')::uuid;
    wallet_id_value uuid := (p_row->>'wallet_id')::uuid;
    ledger_id_value uuid := (p_row->>'ledger_transaction_id')::uuid;
    existing public.investment_wallet_postings%rowtype;
    saved public.investment_wallet_postings%rowtype;
    next_version bigint;
    current_bucket_total bigint;
    requested_delta bigint := (p_row->>'accounting_amount_minor')::bigint;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':investment-cash', 0));
    if not public.has_investment_permission(owner_id, 'edit') then
        raise exception 'Investment edit permission is required';
    end if;
    if coalesce(p_row->>'role_raw_value', '') not in (
        'cashAccrual', 'cashReconciliation', 'cashConsumption', 'cashTransfer', 'cashCorrection'
    ) or coalesce(p_row->>'cash_bucket_raw_value', '') not in ('booked', 'unreconciled')
      or coalesce(p_row->>'cash_origin_raw_value', '') not in ('derived', 'inferred', 'manual') then
        raise exception 'Invalid investment cash posting';
    end if;
    if not exists (
        select 1 from public.ledger_wallets w
        where w.id = wallet_id_value and w.user_id = owner_id
          and w.deleted_at is null and not w.is_archived
    ) then raise exception 'Invalid investment cash wallet'; end if;
    if auth.uid() is distinct from owner_id
       and not public.has_family_permission_grant(owner_id, 'wallet', wallet_id_value, 'use') then
        raise exception 'Wallet use permission is required';
    end if;
    if not exists (
        select 1 from public.ledger_transactions t
        where t.id = ledger_id_value and t.user_id = owner_id and t.deleted_at is null
    ) then raise exception 'Investment cash ledger transaction is missing'; end if;

    select * into existing from public.investment_wallet_postings where id = posting_id for update;
    if existing.id is not null and not p_force and p_expected_version is not null
       and existing.sync_version <> p_expected_version then
        raise exception 'version_conflict';
    end if;

    if nullif(p_row->>'deleted_at', '') is null
       and p_row->>'role_raw_value' in ('cashReconciliation', 'cashConsumption', 'cashTransfer')
       and requested_delta < 0 then
        select coalesce(sum(accounting_amount_minor), 0) into current_bucket_total
        from public.investment_wallet_postings
        where user_id = owner_id
          and wallet_id = wallet_id_value
          and cash_bucket_raw_value = p_row->>'cash_bucket_raw_value'
          and deleted_at is null
          and id <> posting_id;
        if current_bucket_total + requested_delta < 0 then
            raise exception 'Investment cash was already used on another device';
        end if;
    end if;

    if nullif(p_row->>'deleted_at', '') is null
       and p_row->>'role_raw_value' = 'cashReconciliation'
       and p_row->>'cash_bucket_raw_value' = 'unreconciled' then
        select coalesce(sum(accounting_amount_minor), 0) into current_bucket_total
        from public.investment_wallet_postings
        where user_id = owner_id
          and wallet_id = wallet_id_value
          and cash_bucket_raw_value = 'unreconciled'
          and deleted_at is null
          and id <> posting_id;
        if current_bucket_total = 0
           or sign(current_bucket_total) = sign(requested_delta)
           or abs(requested_delta) > abs(current_bucket_total) then
            raise exception 'Investment cash was already reconciled on another device';
        end if;
    end if;
    next_version := case when existing.id is null then 1 else existing.sync_version + 1 end;

    insert into public.investment_wallet_postings (
        id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
        role_raw_value, cash_bucket_raw_value, cash_origin_raw_value,
        amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
        occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id
    ) values (
        posting_id, owner_id, (p_row->>'event_id')::uuid,
        nullif(p_row->>'trade_id', '')::uuid, nullif(p_row->>'asset_id', '')::uuid,
        wallet_id_value, ledger_id_value, p_row->>'role_raw_value',
        p_row->>'cash_bucket_raw_value', p_row->>'cash_origin_raw_value',
        (p_row->>'amount_minor')::bigint, p_row->>'currency_code',
        (p_row->>'accounting_amount_minor')::bigint, p_row->>'accounting_currency_code',
        (p_row->>'occurred_at')::timestamptz, (p_row->>'created_at')::timestamptz,
        (p_row->>'updated_at')::timestamptz, nullif(p_row->>'deleted_at', '')::timestamptz,
        next_version, nullif(p_row->>'last_modified_by_device_id', '')::uuid
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
        deleted_at = excluded.deleted_at,
        sync_version = next_version,
        last_modified_by_device_id = excluded.last_modified_by_device_id
    returning * into saved;
    return saved;
end;
$$;

revoke execute on function public.mutate_investment_cash_posting(jsonb, bigint, boolean) from public, anon;
grant execute on function public.mutate_investment_cash_posting(jsonb, bigint, boolean) to authenticated;

create or replace function public.mutate_investment_cash_postings(
    p_rows jsonb,
    p_force boolean default false
)
returns setof public.investment_wallet_postings
language plpgsql
security definer
set search_path = public
as $$
declare
    owner_id uuid;
    linked_wallet_id uuid;
    reconciliation_event record;
    holder_row jsonb;
    booked_row jsonb;
    current_holder_cash bigint;
    holder_delta bigint;
    saved public.investment_wallet_postings%rowtype;
    row_value jsonb;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
        raise exception 'At least one investment cash posting is required';
    end if;
    select (value->>'user_id')::uuid into owner_id from jsonb_array_elements(p_rows) limit 1;
    if exists (
        select 1 from jsonb_array_elements(p_rows) row_item
        where (row_item.value->>'user_id')::uuid is distinct from owner_id
    ) then
        raise exception 'A cash batch must belong to one owner';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':investment-cash', 0));
    if not public.has_investment_permission(owner_id, 'edit') then
        raise exception 'Investment edit permission is required';
    end if;
    select investment_linked_wallet_id into linked_wallet_id
    from public.ledger_wallets
    where id = public.investment_system_wallet_id(owner_id)
    for share;

    for reconciliation_event in
        select value->>'event_id' as event_id
        from jsonb_array_elements(p_rows)
        where value->>'role_raw_value' = 'cashReconciliation'
        group by value->>'event_id'
    loop
        if (
            select count(*) from jsonb_array_elements(p_rows)
            where value->>'role_raw_value' = 'cashReconciliation'
              and value->>'event_id' = reconciliation_event.event_id
        ) <> 2 then
            raise exception 'A reconciliation event must contain exactly two postings';
        end if;
        select value into holder_row
        from jsonb_array_elements(p_rows)
        where value->>'role_raw_value' = 'cashReconciliation'
          and value->>'event_id' = reconciliation_event.event_id
          and (value->>'wallet_id')::uuid is distinct from linked_wallet_id;
        select value into booked_row
        from jsonb_array_elements(p_rows)
        where value->>'role_raw_value' = 'cashReconciliation'
          and value->>'event_id' = reconciliation_event.event_id
          and (value->>'wallet_id')::uuid = linked_wallet_id;
        if holder_row is null or booked_row is null
           or holder_row->>'cash_bucket_raw_value' <> 'booked'
           or booked_row->>'cash_bucket_raw_value' <> 'booked' then
            raise exception 'A reconciliation must move between a holder and the linked wallet';
        end if;
        holder_delta := (holder_row->>'accounting_amount_minor')::bigint;
        if holder_delta + (booked_row->>'accounting_amount_minor')::bigint <> 0 then
            raise exception 'Reconciliation postings must balance to zero';
        end if;
        select coalesce(sum(accounting_amount_minor), 0) into current_holder_cash
        from public.investment_wallet_postings
        where user_id = owner_id
          and wallet_id = (holder_row->>'wallet_id')::uuid
          and cash_bucket_raw_value = 'booked'
          and deleted_at is null
          and id not in (
              select (value->>'id')::uuid from jsonb_array_elements(p_rows)
          );
        if holder_delta >= 0
           or current_holder_cash <= 0
           or abs(holder_delta) > current_holder_cash then
            raise exception 'Transfer exceeds the investment profit held by this wallet';
        end if;
    end loop;

    for row_value in select value from jsonb_array_elements(p_rows)
    loop
        saved := public.mutate_investment_cash_posting(row_value, null, p_force);
        return next saved;
    end loop;
    return;
end;
$$;

revoke execute on function public.mutate_investment_cash_postings(jsonb, boolean) from public, anon;
grant execute on function public.mutate_investment_cash_postings(jsonb, boolean) to authenticated;

-- Preserve already-confirmed transfers created by the previous migration. The
-- holder posting becomes booked and the ledger transfer is attached to the two
-- real wallets, including its original-currency amounts.
with legacy_reconciliation as (
    select
        holder.id as holder_posting_id,
        holder.ledger_transaction_id,
        holder.wallet_id as holder_wallet_id,
        linked.wallet_id as linked_wallet_id,
        holder.accounting_amount_minor as holder_accounting_delta,
        holder.amount_minor as holder_local_delta,
        linked.amount_minor as linked_local_delta,
        holder_wallet.currency_code as holder_currency_code,
        linked_wallet.currency_code as linked_currency_code
    from public.investment_wallet_postings holder
    join public.investment_wallet_postings linked
      on linked.event_id = holder.event_id
     and linked.role_raw_value = 'cashReconciliation'
     and linked.cash_bucket_raw_value = 'booked'
     and linked.id <> holder.id
    join public.ledger_wallets holder_wallet on holder_wallet.id = holder.wallet_id
    join public.ledger_wallets linked_wallet on linked_wallet.id = linked.wallet_id
    where holder.role_raw_value = 'cashReconciliation'
      and holder.cash_bucket_raw_value = 'unreconciled'
      and holder.deleted_at is null
      and linked.deleted_at is null
), updated_legacy_ledgers as (
    update public.ledger_transactions ledger_row
    set source_wallet_id = case
            when legacy.holder_accounting_delta < 0 then legacy.holder_wallet_id
            else legacy.linked_wallet_id
        end,
        destination_wallet_id = case
            when legacy.holder_accounting_delta < 0 then legacy.linked_wallet_id
            else legacy.holder_wallet_id
        end,
        source_currency_code = case
            when legacy.holder_accounting_delta < 0 then legacy.holder_currency_code
            else legacy.linked_currency_code
        end,
        destination_currency_code = case
            when legacy.holder_accounting_delta < 0 then legacy.linked_currency_code
            else legacy.holder_currency_code
        end,
        amount_minor = case
            when legacy.holder_accounting_delta < 0 then abs(legacy.holder_local_delta)
            else abs(legacy.linked_local_delta)
        end,
        destination_amount_minor = case
            when legacy.holder_accounting_delta < 0 then abs(legacy.linked_local_delta)
            else abs(legacy.holder_local_delta)
        end,
        updated_at = now(),
        sync_version = ledger_row.sync_version + 1
    from legacy_reconciliation legacy
    where ledger_row.id = legacy.ledger_transaction_id
    returning legacy.holder_posting_id
)
update public.investment_wallet_postings holder
set cash_bucket_raw_value = 'booked',
    updated_at = now(),
    sync_version = holder.sync_version + 1
from updated_legacy_ledgers updated
where holder.id = updated.holder_posting_id;

-- Rebook every sale profit/loss leg to the wallet that received the sale. The
-- trigger above also rebuilds its booked cash-allocation posting idempotently.
with sale_profit_locations as (
    select
        profit.id as posting_id,
        trade.capital_return_wallet_id as target_wallet_id,
        target_wallet.currency_code as target_currency_code,
        case
            when upper(target_wallet.currency_code) = upper(profit.accounting_currency_code)
                then profit.accounting_amount_minor
            when coalesce(trade.accounting_to_capital_return_rate_decimal_string, '') <> ''
                then round(
                    trade.accounting_gross_amount_minor::numeric
                    * trade.accounting_to_capital_return_rate_decimal_string::numeric
                )::bigint - coalesce(trade.capital_return_wallet_amount_minor, 0)
            else profit.accounting_amount_minor
        end as target_amount_minor
    from public.investment_wallet_postings profit
    join public.investment_trades trade on trade.id = profit.trade_id
    join public.ledger_wallets target_wallet on target_wallet.id = trade.capital_return_wallet_id
    where profit.role_raw_value = 'realizedProfit'
      and trade.capital_return_wallet_id is not null
)
update public.investment_wallet_postings profit
set wallet_id = location.target_wallet_id,
    amount_minor = location.target_amount_minor,
    currency_code = location.target_currency_code,
    updated_at = now(),
    sync_version = profit.sync_version + 1
from sale_profit_locations location
where profit.id = location.posting_id;
