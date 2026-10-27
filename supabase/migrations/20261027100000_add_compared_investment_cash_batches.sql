-- Backward-compatible overload: the legacy two-argument RPC remains unchanged.
-- New callers compare every posting explicitly; financial checks and the batch
-- transaction stay identical to the existing owner-locked cash batch contract.
create or replace function public.mutate_investment_cash_postings(
    p_rows jsonb,
    p_expected_versions jsonb,
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
    existing public.investment_wallet_postings%rowtype;
    row_id text;
    expected_value jsonb;
    expected_version bigint;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if p_force is not false then
        raise exception 'investment_cash_force_not_allowed';
    end if;
    if p_rows is null or jsonb_typeof(p_rows) is distinct from 'array' then
        raise exception 'investment_cash_invalid_batch';
    end if;
    if jsonb_array_length(p_rows) = 0 then
        raise exception 'investment_cash_invalid_batch';
    end if;
    for row_value in select value from jsonb_array_elements(p_rows)
    loop
        if jsonb_typeof(row_value) is distinct from 'object'
           or jsonb_typeof(row_value->'id') is distinct from 'string'
           or jsonb_typeof(row_value->'user_id') is distinct from 'string'
           or coalesce(row_value->>'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           or coalesce(row_value->>'user_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
            raise exception 'investment_cash_invalid_batch';
        end if;
    end loop;
    if (select count(distinct value->>'id') from jsonb_array_elements(p_rows)) <> jsonb_array_length(p_rows) then
        raise exception 'investment_cash_invalid_batch';
    end if;
    if p_expected_versions is null or jsonb_typeof(p_expected_versions) is distinct from 'object' then
        raise exception 'investment_cash_invalid_expected_versions';
    end if;
    if (select count(*) from jsonb_each(p_expected_versions)) <> jsonb_array_length(p_rows) then
        raise exception 'investment_cash_invalid_expected_versions';
    end if;
    for row_value in select value from jsonb_array_elements(p_rows)
    loop
        expected_value := p_expected_versions->(row_value->>'id');
        if jsonb_typeof(expected_value) is distinct from 'number'
           or expected_value::text !~ '^(0|[1-9][0-9]*)$'
           or length(expected_value::text) > 19 then
            raise exception 'investment_cash_invalid_expected_versions';
        end if;
        if (expected_value::text)::numeric > 9223372036854775806 then
            raise exception 'investment_cash_invalid_expected_versions';
        end if;
    end loop;
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
    -- Compare all requested rows before financial writes; the owner lock is shared
    -- with the legacy batch, the hardened single-row RPC and cash-event mutation.
    for row_value in select value from jsonb_array_elements(p_rows) order by value->>'id'
    loop
        row_id := row_value->>'id';
        expected_version := (p_expected_versions->>row_id)::bigint;
        select * into existing from public.investment_wallet_postings where id = row_id::uuid for update;
        if existing.id is not null and existing.user_id is distinct from owner_id then
            raise exception 'Invalid investment cash posting';
        end if;
        if (existing.id is null and expected_version <> 0)
           or (existing.id is not null and existing.sync_version <> expected_version) then
            raise exception 'version_conflict';
        end if;
    end loop;
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
        saved := public.mutate_investment_cash_posting(row_value, (p_expected_versions->>(row_value->>'id'))::bigint, false);
        return next saved;
    end loop;
    return;
end;
$$;

revoke execute on function public.mutate_investment_cash_postings(jsonb, jsonb, boolean) from public, anon;
grant execute on function public.mutate_investment_cash_postings(jsonb, jsonb, boolean) to authenticated;
