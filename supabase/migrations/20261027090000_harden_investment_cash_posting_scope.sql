-- Preserve the existing single/bulk cash allocation API and valid legacy nil-version calls.
-- Force may resolve a same-owner version conflict; it never changes ownership authority.
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
    -- The caller's owner permission never grants authority over a foreign global ID.
    if existing.id is not null and existing.user_id is distinct from owner_id then
        raise exception 'Invalid investment cash posting';
    end if;
    if existing.id is null and p_force is not true
       and coalesce(p_expected_version, 0) <> 0 then
        raise exception 'version_conflict';
    end if;
    if existing.id is not null and p_force is not true and p_expected_version is not null
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
    -- A foreign insert can win after our initial absent-row read. Do not redirect it.
    where public.investment_wallet_postings.user_id = owner_id
    returning * into saved;
    if saved.id is null then
        raise exception 'Invalid investment cash posting';
    end if;
    return saved;
end;
$$;

revoke execute on function public.mutate_investment_cash_posting(jsonb, bigint, boolean) from public, anon;
grant execute on function public.mutate_investment_cash_posting(jsonb, bigint, boolean) to authenticated;
