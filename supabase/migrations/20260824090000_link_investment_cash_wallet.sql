-- Investment cash locations and one linked real wallet per owner.
-- Cash postings remain server-controlled and share investment_wallet_postings.

alter table public.ledger_wallets
    add column if not exists investment_linked_wallet_id uuid
        references public.ledger_wallets(id) on delete restrict;

alter table public.investment_wallet_postings
    add column if not exists cash_bucket_raw_value text,
    add column if not exists cash_origin_raw_value text;

alter table public.investment_wallet_postings
    drop constraint if exists investment_wallet_postings_role_raw_value_check,
    add constraint investment_wallet_postings_role_raw_value_check check (
        role_raw_value in (
            'funding', 'capitalReturn', 'realizedProfit', 'transferOut', 'transferIn',
            'cashAccrual', 'cashReconciliation', 'cashConsumption', 'cashTransfer', 'cashCorrection'
        )
    ),
    add constraint investment_wallet_postings_cash_bucket_check check (
        cash_bucket_raw_value is null or cash_bucket_raw_value in ('booked', 'unreconciled')
    ),
    add constraint investment_wallet_postings_cash_origin_check check (
        cash_origin_raw_value is null or cash_origin_raw_value in ('derived', 'inferred', 'manual')
    ),
    add constraint investment_wallet_postings_cash_shape_check check (
        (role_raw_value like 'cash%' and cash_bucket_raw_value is not null and cash_origin_raw_value is not null)
        or (role_raw_value not like 'cash%' and cash_bucket_raw_value is null and cash_origin_raw_value is null)
    );

create index if not exists investment_postings_cash_location_idx
    on public.investment_wallet_postings(user_id, wallet_id, cash_bucket_raw_value, occurred_at, id)
    where deleted_at is null and cash_bucket_raw_value is not null;

create or replace function public.enforce_investment_linked_wallet()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    linked public.ledger_wallets%rowtype;
    retained_minor bigint;
begin
    if new.system_purpose_raw_value = 'investmentProfit' and new.investment_linked_wallet_id is not null then
        select * into linked
        from public.ledger_wallets
        where id = new.investment_linked_wallet_id
        for share;
        if linked.id is null
           or linked.user_id <> new.user_id
           or linked.currency_code <> new.currency_code
           or linked.deleted_at is not null
           or linked.is_archived
           or linked.kind_raw_value in ('creditCard', 'investment')
           or linked.system_purpose_raw_value is not null then
            raise exception 'Invalid linked investment wallet';
        end if;
        if auth.uid() is distinct from new.user_id
           and not public.has_family_permission_grant(new.user_id, 'wallet', linked.id, 'use') then
            raise exception 'Wallet use permission is required';
        end if;
        if not public.has_investment_permission(new.user_id, 'edit') then
            raise exception 'Investment edit permission is required';
        end if;
    elsif new.system_purpose_raw_value is null and new.investment_linked_wallet_id is not null then
        raise exception 'Only the system Investment Wallet can have a linked wallet';
    end if;

    if tg_op = 'UPDATE' and old.system_purpose_raw_value is null then
        if exists (
            select 1 from public.ledger_wallets system_wallet
            where system_wallet.investment_linked_wallet_id = old.id
              and system_wallet.deleted_at is null
        ) and (
            new.user_id is distinct from old.user_id
            or new.currency_code is distinct from old.currency_code
            or new.kind_raw_value is distinct from old.kind_raw_value
            or new.is_archived
            or new.deleted_at is not null
        ) then
            raise exception 'Move investment cash and unlink this wallet before changing or archiving it';
        end if;

        select coalesce(sum(accounting_amount_minor), 0) into retained_minor
        from public.investment_wallet_postings
        where wallet_id = old.id and deleted_at is null and cash_bucket_raw_value is not null;
        if retained_minor <> 0 and (
            new.user_id is distinct from old.user_id
            or new.currency_code is distinct from old.currency_code
            or new.kind_raw_value is distinct from old.kind_raw_value
            or new.is_archived
            or new.deleted_at is not null
        ) then
            raise exception 'Move or adjust the investment cash held by this wallet first';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists ledger_wallets_enforce_investment_linked_wallet on public.ledger_wallets;
create trigger ledger_wallets_enforce_investment_linked_wallet
before insert or update on public.ledger_wallets
for each row execute function public.enforce_investment_linked_wallet();

revoke execute on function public.enforce_investment_linked_wallet() from public, anon, authenticated;

create or replace function public.sync_investment_cash_accrual()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    trade_row public.investment_trades%rowtype;
    system_wallet public.ledger_wallets%rowtype;
    target_wallet public.ledger_wallets%rowtype;
    target_bucket text;
    cash_posting_id uuid;
    target_amount_minor bigint;
begin
    if new.role_raw_value <> 'realizedProfit' then
        return null;
    end if;
    select * into trade_row from public.investment_trades where id = new.trade_id;
    if trade_row.id is null or trade_row.capital_return_wallet_id is null then return null; end if;
    select * into system_wallet from public.ledger_wallets
    where id = public.investment_system_wallet_id(new.user_id);
    select * into target_wallet from public.ledger_wallets where id = trade_row.capital_return_wallet_id;
    target_bucket := case
        when system_wallet.investment_linked_wallet_id = target_wallet.id then 'booked'
        else 'unreconciled'
    end;
    target_amount_minor := case
        when upper(target_wallet.currency_code) = upper(new.accounting_currency_code)
            then new.accounting_amount_minor
        when coalesce(trade_row.accounting_to_capital_return_rate_decimal_string, '') <> ''
            then round(
                new.accounting_amount_minor::numeric
                * trade_row.accounting_to_capital_return_rate_decimal_string::numeric
            )::bigint
        else new.accounting_amount_minor
    end;
    cash_posting_id := public.investment_ledger_id(new.event_id, 'cash-accrual-posting');

    if target_bucket = 'booked' then
        update public.ledger_transactions
        set source_wallet_id = target_wallet.id,
            source_currency_code = target_wallet.currency_code,
            updated_at = new.updated_at,
            sync_version = sync_version + 1
        where id = new.ledger_transaction_id
          and source_wallet_id is distinct from target_wallet.id;
        update public.investment_wallet_postings
        set wallet_id = target_wallet.id,
            currency_code = target_wallet.currency_code,
            updated_at = new.updated_at,
            sync_version = sync_version + 1
        where id = new.id and wallet_id is distinct from target_wallet.id;
    end if;

    insert into public.investment_wallet_postings (
        id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
        role_raw_value, cash_bucket_raw_value, cash_origin_raw_value,
        amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
        occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id
    ) values (
        cash_posting_id, new.user_id, new.event_id, new.trade_id, new.asset_id,
        target_wallet.id, new.ledger_transaction_id, 'cashAccrual', target_bucket, 'derived',
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

drop trigger if exists investment_postings_sync_cash_accrual on public.investment_wallet_postings;
create trigger investment_postings_sync_cash_accrual
after insert or update on public.investment_wallet_postings
for each row execute function public.sync_investment_cash_accrual();

revoke execute on function public.sync_investment_cash_accrual() from public, anon, authenticated;

-- Idempotent, advisory-locked write path for manual reconciliation, consumption,
-- transfers and corrections generated by the shared app coordinator.
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
       and p_row->>'role_raw_value' in ('cashConsumption', 'cashTransfer')
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

-- Batch path used by reconciliation/consumption coordinators. Reconciliation
-- pairs are validated and written while holding one owner-scoped advisory lock,
-- so two devices cannot both collect the same outstanding amount.
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
    current_unreconciled bigint;
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
          and value->>'cash_bucket_raw_value' = 'unreconciled';
        select value into booked_row
        from jsonb_array_elements(p_rows)
        where value->>'role_raw_value' = 'cashReconciliation'
          and value->>'event_id' = reconciliation_event.event_id
          and value->>'cash_bucket_raw_value' = 'booked';
        if holder_row is null or booked_row is null
           or (booked_row->>'wallet_id')::uuid is distinct from linked_wallet_id then
            raise exception 'A reconciliation must move between a holder and the linked wallet';
        end if;
        holder_delta := (holder_row->>'accounting_amount_minor')::bigint;
        if holder_delta + (booked_row->>'accounting_amount_minor')::bigint <> 0 then
            raise exception 'Reconciliation postings must balance to zero';
        end if;
        select coalesce(sum(accounting_amount_minor), 0) into current_unreconciled
        from public.investment_wallet_postings
        where user_id = owner_id
          and wallet_id = (holder_row->>'wallet_id')::uuid
          and cash_bucket_raw_value = 'unreconciled'
          and deleted_at is null
          and id not in (
              select (value->>'id')::uuid from jsonb_array_elements(p_rows)
          );
        if current_unreconciled = 0
           or sign(current_unreconciled) = sign(holder_delta)
           or abs(holder_delta) > abs(current_unreconciled) then
            raise exception 'Reconciliation exceeds the outstanding investment cash';
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

-- Historical sales become inferred locations. Old outbound transfers remain
-- visible as legacy postings and can be corrected from the app if attribution is ambiguous.
insert into public.investment_wallet_postings (
    id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
    role_raw_value, cash_bucket_raw_value, cash_origin_raw_value,
    amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
    occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id
)
select
    public.investment_ledger_id(p.event_id, 'cash-accrual-posting'), p.user_id, p.event_id,
    p.trade_id, p.asset_id, t.capital_return_wallet_id, p.ledger_transaction_id,
    'cashAccrual',
    case when system_wallet.investment_linked_wallet_id = t.capital_return_wallet_id then 'booked' else 'unreconciled' end,
    'inferred',
    case
        when upper(target_wallet.currency_code) = upper(p.accounting_currency_code)
            then p.accounting_amount_minor
        when coalesce(t.accounting_to_capital_return_rate_decimal_string, '') <> ''
            then round(
                p.accounting_amount_minor::numeric
                * t.accounting_to_capital_return_rate_decimal_string::numeric
            )::bigint
        else p.accounting_amount_minor
    end,
    target_wallet.currency_code,
    p.accounting_amount_minor, p.accounting_currency_code,
    p.occurred_at, p.created_at, p.updated_at, p.deleted_at, 1, p.last_modified_by_device_id
from public.investment_wallet_postings p
join public.investment_trades t on t.id = p.trade_id
join public.ledger_wallets system_wallet on system_wallet.id = public.investment_system_wallet_id(p.user_id)
join public.ledger_wallets target_wallet on target_wallet.id = t.capital_return_wallet_id
where p.role_raw_value = 'realizedProfit' and t.capital_return_wallet_id is not null
on conflict (id) do nothing;
