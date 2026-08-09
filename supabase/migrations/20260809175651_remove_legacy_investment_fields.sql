-- Remove legacy investment fields from canonical cloud storage.
-- Existing opening positions and fees are intentionally discarded, then all
-- server-derived trade snapshots, wallet postings, and ledger rows are rebuilt.

drop trigger if exists investment_channels_source_integrity on public.investment_channels;
drop trigger if exists investment_assets_source_integrity on public.investment_assets;

update public.investment_assets
set symbol = null,
    opening_quantity_decimal_string = '0',
    opening_cost_minor = 0;

update public.investment_trades
set fee_minor = 0,
    accounting_fee_minor = 0;

do $migration$
declare
    asset_row record;
    migration_now timestamptz := timezone('utc'::text, now());
begin
    for asset_row in
        select id, user_id
        from public.investment_assets
        order by user_id, id
    loop
        perform set_config('request.jwt.claim.sub', asset_row.user_id::text, true);
        perform set_config(
            'request.jwt.claims',
            jsonb_build_object('sub', asset_row.user_id, 'role', 'authenticated')::text,
            true
        );
        perform public.investment_rebuild_asset(
            asset_row.user_id,
            asset_row.id,
            asset_row.user_id,
            null,
            migration_now
        );
    end loop;
end;
$migration$;

create or replace function public.enforce_investment_source_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    current_quantity numeric;
    related_asset public.investment_assets%rowtype;
    accounting_wallet public.ledger_wallets%rowtype;
begin
    if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
        raise exception 'Investment ownership is immutable';
    end if;

    if tg_table_name = 'investment_channels' then
        if tg_op <> 'DELETE' and nullif(btrim(new.name), '') is null then
            raise exception 'Investment channel name is required';
        end if;
        if (
            tg_op = 'DELETE'
            or (tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null)
        ) and exists (
            select 1 from public.investment_assets asset
            where asset.channel_id = old.id
        ) then
            raise exception 'Investment channels with history must be archived';
        end if;
        if tg_op = 'UPDATE' and old.is_archived = false and new.is_archived = true and exists (
            select 1
            from public.investment_assets asset
            where asset.channel_id = old.id
              and asset.deleted_at is null
              and coalesce(
                  (
                      select trade.position_quantity_after_decimal_string::numeric
                      from public.investment_trades trade
                      where trade.asset_id = asset.id and trade.deleted_at is null
                      order by trade.occurred_at desc, trade.created_at desc, trade.id desc
                      limit 1
                  ),
                  0
              ) > 0
        ) then
            raise exception 'Close all positions before archiving the investment channel';
        end if;
    elsif tg_table_name = 'investment_assets' then
        if tg_op <> 'DELETE' and nullif(btrim(new.name), '') is null then
            raise exception 'Investment asset name is required';
        end if;
        if tg_op = 'UPDATE' and exists (
            select 1 from public.investment_trades trade where trade.asset_id = old.id
            union all
            select 1 from public.investment_valuations valuation where valuation.asset_id = old.id
        ) and (
            old.channel_id is distinct from new.channel_id
            or old.currency_code is distinct from new.currency_code
        ) then
            raise exception 'Asset channel and currency are immutable after history exists';
        end if;
        if (
            tg_op = 'DELETE'
            or (tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null)
        ) and (
            exists (select 1 from public.investment_trades trade where trade.asset_id = old.id)
            or exists (select 1 from public.investment_valuations valuation where valuation.asset_id = old.id)
        ) then
            raise exception 'Investment assets with history must be archived';
        end if;
        if tg_op = 'UPDATE' and old.is_archived = false and new.is_archived = true then
            select coalesce(
                (
                    select trade.position_quantity_after_decimal_string::numeric
                    from public.investment_trades trade
                    where trade.asset_id = old.id and trade.deleted_at is null
                    order by trade.occurred_at desc, trade.created_at desc, trade.id desc
                    limit 1
                ),
                0
            ) into current_quantity;
            if current_quantity > 0 then
                raise exception 'Close the position before archiving the investment asset';
            end if;
        end if;
    elsif tg_table_name = 'investment_valuations' then
        if tg_op = 'UPDATE' and (
            old.channel_id is distinct from new.channel_id
            or old.asset_id is distinct from new.asset_id
        ) then
            raise exception 'Investment valuation relationships are immutable';
        end if;
        if tg_op <> 'DELETE' then
            select * into related_asset
            from public.investment_assets
            where id = new.asset_id
              and channel_id = new.channel_id
              and user_id = new.user_id
              and deleted_at is null;
            select * into accounting_wallet
            from public.ledger_wallets
            where id = public.investment_system_wallet_id(new.user_id)
              and user_id = new.user_id
              and system_purpose_raw_value = 'investmentProfit'
              and deleted_at is null;
            if related_asset.id is null
               or accounting_wallet.id is null
               or upper(new.currency_code) <> upper(related_asset.currency_code)
               or upper(new.accounting_currency_code) <> upper(accounting_wallet.currency_code)
               or (
                    upper(new.currency_code) = upper(new.accounting_currency_code)
                    and new.market_value_minor <> new.accounting_market_value_minor
               )
               or (
                    upper(new.currency_code) <> upper(new.accounting_currency_code)
                    and (
                        coalesce(new.exchange_rate_decimal_string, '') = ''
                        or new.exchange_rate_decimal_string::numeric <= 0
                        or round(
                            new.market_value_minor::numeric
                            * new.exchange_rate_decimal_string::numeric
                        )::bigint <> new.accounting_market_value_minor
                    )
               ) then
                raise exception 'Invalid investment valuation snapshot';
            end if;
        end if;
    end if;

    if tg_op = 'DELETE' then return old; end if;
    return new;
end;
$$;

create trigger investment_channels_source_integrity
before insert or update or delete on public.investment_channels
for each row execute function public.enforce_investment_source_integrity();

create trigger investment_assets_source_integrity
before insert or update or delete on public.investment_assets
for each row execute function public.enforce_investment_source_integrity();

create or replace function public.investment_rebuild_asset(
    p_owner_user_id uuid,
    p_asset_id uuid,
    p_actor_user_id uuid,
    p_device_id uuid,
    p_now timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    asset_row public.investment_assets%rowtype;
    trade_row public.investment_trades%rowtype;
    wallet_row public.ledger_wallets%rowtype;
    system_wallet public.ledger_wallets%rowtype;
    position_quantity numeric;
    position_cost bigint;
    released_cost bigint;
    realized_profit bigint;
    funding_amount bigint;
    capital_amount bigint;
    funding_ledger_id uuid;
    capital_ledger_id uuid;
    profit_ledger_id uuid;
    keep_ledger_ids uuid[];
    keep_posting_ids uuid[];
begin
    select * into asset_row
    from public.investment_assets
    where id = p_asset_id and user_id = p_owner_user_id
    for update;
    if asset_row.id is null then raise exception 'Investment asset not found'; end if;

    select * into system_wallet
    from public.ledger_wallets
    where id = public.investment_system_wallet_id(p_owner_user_id)
      and user_id = p_owner_user_id
      and system_purpose_raw_value = 'investmentProfit'
      and deleted_at is null
    for update;
    if system_wallet.id is null then raise exception 'System Investment Wallet not found'; end if;

    update public.investment_wallet_postings
    set deleted_at = p_now, updated_at = p_now, sync_version = sync_version + 1,
        last_modified_by_device_id = p_device_id
    where user_id = p_owner_user_id
      and trade_id in (select id from public.investment_trades where asset_id = p_asset_id)
      and deleted_at is null;

    update public.ledger_transactions
    set deleted_at = p_now, updated_at = p_now, sync_version = sync_version + 1,
        last_modified_by_device_id = p_device_id,
        last_modified_by_user_id = p_actor_user_id
    where user_id = p_owner_user_id
      and id in (
          select funding_ledger_transaction_id from public.investment_trades where asset_id = p_asset_id
          union select capital_return_ledger_transaction_id from public.investment_trades where asset_id = p_asset_id
          union select profit_loss_ledger_transaction_id from public.investment_trades where asset_id = p_asset_id
      )
      and deleted_at is null;

    position_quantity := 0;
    position_cost := 0;

    for trade_row in
        select * from public.investment_trades
        where user_id = p_owner_user_id and asset_id = p_asset_id and deleted_at is null
        order by occurred_at, created_at, id
        for update
    loop
        if trade_row.quantity_decimal_string::numeric <= 0
           or trade_row.accounting_gross_amount_minor <= 0
           or upper(trade_row.accounting_currency_code) <> upper(system_wallet.currency_code) then
            raise exception 'Invalid investment trade input';
        end if;

        released_cost := 0;
        realized_profit := 0;
        keep_ledger_ids := array[]::uuid[];
        keep_posting_ids := array[]::uuid[];

        if trade_row.kind_raw_value = 'buy' then
            select * into wallet_row from public.ledger_wallets
            where id = trade_row.funding_wallet_id and user_id = p_owner_user_id and deleted_at is null and is_archived = false
            for update;
            if wallet_row.id is null then raise exception 'Funding wallet not found'; end if;
            if not public.can_operate_wallet(wallet_row.id) then raise exception 'wallet.use is required for the funding wallet'; end if;

            if wallet_row.currency_code = trade_row.accounting_currency_code then
                funding_amount := trade_row.accounting_gross_amount_minor;
            else
                if coalesce(trade_row.funding_to_accounting_rate_decimal_string, '') = ''
                   or trade_row.funding_to_accounting_rate_decimal_string::numeric <= 0 then
                    raise exception 'Funding exchange-rate snapshot is required';
                end if;
                funding_amount := round(
                    (trade_row.accounting_gross_amount_minor)::numeric
                    / trade_row.funding_to_accounting_rate_decimal_string::numeric
                )::bigint;
            end if;
            if funding_amount <= 0 then raise exception 'Invalid funding amount'; end if;

            if wallet_row.kind_raw_value = 'creditCard' then
                if not exists (
                    select 1 from public.credit_card_profiles cp
                    where cp.wallet_id = wallet_row.id and cp.deleted_at is null
                      and wallet_row.current_balance_minor >= funding_amount
                ) then raise exception 'Insufficient available credit'; end if;
            elsif wallet_row.current_balance_minor < funding_amount then
                raise exception 'Insufficient wallet balance';
            end if;

            position_quantity := position_quantity + trade_row.quantity_decimal_string::numeric;
            position_cost := position_cost + trade_row.accounting_gross_amount_minor;
            funding_ledger_id := public.investment_ledger_id(trade_row.id, 'funding');

            insert into public.ledger_transactions (
                id, user_id, primary_kind_raw_value, entry_status_raw_value, title, amount_minor,
                reporting_expense_minor, reporting_income_minor, source_currency_code,
                reporting_currency_code, reporting_amount_minor, occurred_at,
                created_by_user_id, last_modified_by_user_id, source_wallet_id,
                category_id, settlement_role_raw_value, is_archived, created_at, updated_at,
                deleted_at, sync_version, last_modified_by_device_id
            ) values (
                funding_ledger_id, p_owner_user_id, 'expense', 'posted', asset_row.name, funding_amount,
                0, 0, wallet_row.currency_code, trade_row.accounting_currency_code,
                trade_row.accounting_gross_amount_minor,
                trade_row.occurred_at, p_actor_user_id, p_actor_user_id, wallet_row.id,
                null, 'investmentFunding', false, trade_row.created_at, p_now, null, 1, p_device_id
            ) on conflict (id) do update set
                primary_kind_raw_value = excluded.primary_kind_raw_value,
                entry_status_raw_value = excluded.entry_status_raw_value,
                title = excluded.title, amount_minor = excluded.amount_minor,
                reporting_expense_minor = 0, reporting_income_minor = 0,
                source_currency_code = excluded.source_currency_code,
                destination_currency_code = null, destination_amount_minor = null,
                reporting_currency_code = excluded.reporting_currency_code,
                reporting_amount_minor = excluded.reporting_amount_minor,
                occurred_at = excluded.occurred_at, source_wallet_id = excluded.source_wallet_id,
                destination_wallet_id = null, category_id = null,
                settlement_role_raw_value = 'investmentFunding', is_archived = false,
                archived_at = null, deleted_at = null, updated_at = p_now,
                last_modified_by_user_id = p_actor_user_id,
                last_modified_by_device_id = p_device_id,
                sync_version = public.ledger_transactions.sync_version + 1;

            insert into public.investment_wallet_postings (
                id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
                role_raw_value, amount_minor, currency_code, accounting_amount_minor,
                accounting_currency_code, occurred_at, created_at, updated_at, deleted_at,
                sync_version, last_modified_by_device_id
            ) values (
                public.investment_ledger_id(trade_row.id, 'funding-posting'), p_owner_user_id,
                trade_row.id, trade_row.id, trade_row.asset_id, wallet_row.id, funding_ledger_id,
                'funding', -funding_amount, wallet_row.currency_code,
                -(trade_row.accounting_gross_amount_minor),
                trade_row.accounting_currency_code, trade_row.occurred_at, trade_row.created_at,
                p_now, null, 1, p_device_id
            ) on conflict (id) do update set
                wallet_id = excluded.wallet_id, ledger_transaction_id = excluded.ledger_transaction_id,
                amount_minor = excluded.amount_minor, currency_code = excluded.currency_code,
                accounting_amount_minor = excluded.accounting_amount_minor,
                accounting_currency_code = excluded.accounting_currency_code,
                occurred_at = excluded.occurred_at, deleted_at = null, updated_at = p_now,
                last_modified_by_device_id = p_device_id,
                sync_version = public.investment_wallet_postings.sync_version + 1;

            update public.investment_trades set
                funding_wallet_currency_code = wallet_row.currency_code,
                capital_return_wallet_currency_code = null,
                funding_wallet_amount_minor = funding_amount,
                capital_return_wallet_amount_minor = null,
                funding_ledger_transaction_id = funding_ledger_id,
                capital_return_ledger_transaction_id = null,
                profit_loss_ledger_transaction_id = null,
                released_cost_basis_minor = 0,
                realized_profit_loss_minor = 0,
                position_quantity_after_decimal_string = position_quantity::text,
                position_cost_basis_after_minor = position_cost,
                updated_at = p_now,
                sync_version = sync_version + 1,
                last_modified_by_device_id = p_device_id
            where id = trade_row.id;
        else
            if position_quantity < trade_row.quantity_decimal_string::numeric then
                raise exception 'Sale exceeds the quantity held';
            end if;
            select * into wallet_row from public.ledger_wallets
            where id = trade_row.capital_return_wallet_id and user_id = p_owner_user_id
              and deleted_at is null and is_archived = false
              and system_purpose_raw_value is null and kind_raw_value <> 'creditCard'
            for update;
            if wallet_row.id is null then raise exception 'Capital return wallet must be an ordinary wallet'; end if;
            if not public.can_operate_wallet(wallet_row.id) then raise exception 'wallet.use is required for the capital return wallet'; end if;

            if position_quantity = trade_row.quantity_decimal_string::numeric then
                released_cost := position_cost;
            else
                released_cost := round(
                    position_cost::numeric * trade_row.quantity_decimal_string::numeric / position_quantity
                )::bigint;
            end if;
            realized_profit := trade_row.accounting_gross_amount_minor - released_cost;
            position_quantity := position_quantity - trade_row.quantity_decimal_string::numeric;
            position_cost := position_cost - released_cost;
            if position_quantity = 0 then position_cost := 0; end if;

            if wallet_row.currency_code = trade_row.accounting_currency_code then
                capital_amount := released_cost;
            else
                if coalesce(trade_row.accounting_to_capital_return_rate_decimal_string, '') = ''
                   or trade_row.accounting_to_capital_return_rate_decimal_string::numeric <= 0 then
                    raise exception 'Capital-return exchange-rate snapshot is required';
                end if;
                capital_amount := round(released_cost::numeric * trade_row.accounting_to_capital_return_rate_decimal_string::numeric)::bigint;
            end if;
            capital_ledger_id := public.investment_ledger_id(trade_row.id, 'capital-return');

            insert into public.ledger_transactions (
                id, user_id, primary_kind_raw_value, entry_status_raw_value, title, amount_minor,
                reporting_expense_minor, reporting_income_minor, source_currency_code,
                reporting_currency_code, reporting_amount_minor, occurred_at,
                created_by_user_id, last_modified_by_user_id, source_wallet_id,
                category_id, settlement_role_raw_value, is_archived, created_at, updated_at,
                deleted_at, sync_version, last_modified_by_device_id
            ) values (
                capital_ledger_id, p_owner_user_id, 'income', 'posted', asset_row.name, capital_amount,
                0, 0, wallet_row.currency_code, trade_row.accounting_currency_code, released_cost,
                trade_row.occurred_at, p_actor_user_id, p_actor_user_id, wallet_row.id,
                null, 'investmentCapitalReturn', false, trade_row.created_at, p_now, null, 1, p_device_id
            ) on conflict (id) do update set
                primary_kind_raw_value = 'income', entry_status_raw_value = 'posted',
                title = excluded.title, amount_minor = excluded.amount_minor,
                reporting_expense_minor = 0, reporting_income_minor = 0,
                source_currency_code = excluded.source_currency_code,
                destination_currency_code = null, destination_amount_minor = null,
                reporting_currency_code = excluded.reporting_currency_code,
                reporting_amount_minor = excluded.reporting_amount_minor,
                occurred_at = excluded.occurred_at, source_wallet_id = excluded.source_wallet_id,
                destination_wallet_id = null, category_id = null,
                settlement_role_raw_value = 'investmentCapitalReturn', is_archived = false,
                archived_at = null, deleted_at = null, updated_at = p_now,
                last_modified_by_user_id = p_actor_user_id,
                last_modified_by_device_id = p_device_id,
                sync_version = public.ledger_transactions.sync_version + 1;

            insert into public.investment_wallet_postings (
                id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
                role_raw_value, amount_minor, currency_code, accounting_amount_minor,
                accounting_currency_code, occurred_at, created_at, updated_at, deleted_at,
                sync_version, last_modified_by_device_id
            ) values (
                public.investment_ledger_id(trade_row.id, 'capital-return-posting'), p_owner_user_id,
                trade_row.id, trade_row.id, trade_row.asset_id, wallet_row.id, capital_ledger_id,
                'capitalReturn', capital_amount, wallet_row.currency_code, released_cost,
                trade_row.accounting_currency_code, trade_row.occurred_at, trade_row.created_at,
                p_now, null, 1, p_device_id
            ) on conflict (id) do update set
                wallet_id = excluded.wallet_id, ledger_transaction_id = excluded.ledger_transaction_id,
                amount_minor = excluded.amount_minor, currency_code = excluded.currency_code,
                accounting_amount_minor = excluded.accounting_amount_minor,
                accounting_currency_code = excluded.accounting_currency_code,
                occurred_at = excluded.occurred_at, deleted_at = null, updated_at = p_now,
                last_modified_by_device_id = p_device_id,
                sync_version = public.investment_wallet_postings.sync_version + 1;

            profit_ledger_id := null;
            if realized_profit <> 0 then
                profit_ledger_id := public.investment_ledger_id(trade_row.id, 'profit-loss');
                insert into public.ledger_transactions (
                    id, user_id, primary_kind_raw_value, entry_status_raw_value, title, amount_minor,
                    reporting_expense_minor, reporting_income_minor, source_currency_code,
                    reporting_currency_code, reporting_amount_minor, occurred_at,
                    created_by_user_id, last_modified_by_user_id, source_wallet_id,
                    category_id, settlement_role_raw_value, is_archived, created_at, updated_at,
                    deleted_at, sync_version, last_modified_by_device_id
                ) values (
                    profit_ledger_id, p_owner_user_id, case when realized_profit > 0 then 'income' else 'expense' end,
                    'posted', asset_row.name, abs(realized_profit), 0, 0, system_wallet.currency_code,
                    system_wallet.currency_code, abs(realized_profit), trade_row.occurred_at,
                    p_actor_user_id, p_actor_user_id, system_wallet.id, null,
                    'investmentRealizedProfit', false, trade_row.created_at, p_now, null, 1, p_device_id
                ) on conflict (id) do update set
                    primary_kind_raw_value = excluded.primary_kind_raw_value,
                    entry_status_raw_value = 'posted', title = excluded.title,
                    amount_minor = excluded.amount_minor, reporting_expense_minor = 0,
                    reporting_income_minor = 0, source_currency_code = excluded.source_currency_code,
                    destination_currency_code = null, destination_amount_minor = null,
                    reporting_currency_code = excluded.reporting_currency_code,
                    reporting_amount_minor = excluded.reporting_amount_minor,
                    occurred_at = excluded.occurred_at, source_wallet_id = excluded.source_wallet_id,
                    destination_wallet_id = null, category_id = null,
                    settlement_role_raw_value = 'investmentRealizedProfit', is_archived = false,
                    archived_at = null, deleted_at = null, updated_at = p_now,
                    last_modified_by_user_id = p_actor_user_id,
                    last_modified_by_device_id = p_device_id,
                    sync_version = public.ledger_transactions.sync_version + 1;

                insert into public.investment_wallet_postings (
                    id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id,
                    role_raw_value, amount_minor, currency_code, accounting_amount_minor,
                    accounting_currency_code, occurred_at, created_at, updated_at, deleted_at,
                    sync_version, last_modified_by_device_id
                ) values (
                    public.investment_ledger_id(trade_row.id, 'profit-loss-posting'), p_owner_user_id,
                    trade_row.id, trade_row.id, trade_row.asset_id, system_wallet.id, profit_ledger_id,
                    'realizedProfit', realized_profit, system_wallet.currency_code, realized_profit,
                    system_wallet.currency_code, trade_row.occurred_at, trade_row.created_at,
                    p_now, null, 1, p_device_id
                ) on conflict (id) do update set
                    ledger_transaction_id = excluded.ledger_transaction_id,
                    amount_minor = excluded.amount_minor, currency_code = excluded.currency_code,
                    accounting_amount_minor = excluded.accounting_amount_minor,
                    accounting_currency_code = excluded.accounting_currency_code,
                    occurred_at = excluded.occurred_at, deleted_at = null, updated_at = p_now,
                    last_modified_by_device_id = p_device_id,
                    sync_version = public.investment_wallet_postings.sync_version + 1;
            end if;

            update public.investment_trades set
                funding_wallet_currency_code = null,
                capital_return_wallet_currency_code = wallet_row.currency_code,
                funding_wallet_amount_minor = null,
                capital_return_wallet_amount_minor = capital_amount,
                funding_ledger_transaction_id = null,
                capital_return_ledger_transaction_id = capital_ledger_id,
                profit_loss_ledger_transaction_id = profit_ledger_id,
                released_cost_basis_minor = released_cost,
                realized_profit_loss_minor = realized_profit,
                position_quantity_after_decimal_string = position_quantity::text,
                position_cost_basis_after_minor = position_cost,
                updated_at = p_now,
                sync_version = sync_version + 1,
                last_modified_by_device_id = p_device_id
            where id = trade_row.id;
        end if;
    end loop;
end;
$$;

revoke execute on function public.investment_rebuild_asset(uuid, uuid, uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.mutate_investment_trade(
    p_trade jsonb,
    p_expected_version bigint default null,
    p_force boolean default false
)
returns setof public.investment_trades
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    incoming public.investment_trades%rowtype;
    existing public.investment_trades%rowtype;
    asset_row public.investment_assets%rowtype;
    wallet_row public.ledger_wallets%rowtype;
    system_wallet public.ledger_wallets%rowtype;
    now_value timestamptz := timezone('utc'::text, now());
    required_scope text;
begin
    if actor_id is null then raise exception 'Not authenticated'; end if;
    incoming := jsonb_populate_record(null::public.investment_trades, p_trade);
    if incoming.id is null or incoming.user_id is null or incoming.asset_id is null or incoming.channel_id is null then
        raise exception 'Incomplete investment trade';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(lower(incoming.user_id::text || ':' || incoming.asset_id::text), 0));
    select * into existing from public.investment_trades where id = incoming.id for update;
    required_scope := case when existing.id is null then 'create' else 'edit' end;
    if not public.has_investment_permission(incoming.user_id, required_scope) then
        raise exception 'Investment % permission is required', required_scope;
    end if;
    if existing.id is not null and existing.user_id <> incoming.user_id then raise exception 'Investment owner is immutable'; end if;
    if existing.id is not null and (
        existing.asset_id <> incoming.asset_id
        or existing.channel_id <> incoming.channel_id
    ) then
        raise exception 'Investment trade asset and channel are immutable';
    end if;
    if existing.id is not null and p_expected_version is not null
       and existing.sync_version <> p_expected_version and not p_force then
        return;
    end if;
    if existing.id is null and p_expected_version is not null and p_expected_version <> 0 and not p_force then
        return;
    end if;

    select * into asset_row from public.investment_assets
    where id = incoming.asset_id
      and user_id = incoming.user_id
      and channel_id = incoming.channel_id
      and deleted_at is null
      and is_archived = false
      and exists (
          select 1 from public.investment_channels channel
          where channel.id = incoming.channel_id
            and channel.user_id = incoming.user_id
            and channel.deleted_at is null
            and channel.is_archived = false
      );
    if asset_row.id is null then raise exception 'Investment asset/channel mismatch'; end if;
    select * into system_wallet
    from public.ledger_wallets
    where id = public.investment_system_wallet_id(incoming.user_id)
      and user_id = incoming.user_id
      and system_purpose_raw_value = 'investmentProfit'
      and deleted_at is null;
    if system_wallet.id is null then raise exception 'System Investment Wallet not found'; end if;
    if incoming.kind_raw_value not in ('buy', 'sell')
       or incoming.quantity_decimal_string::numeric <= 0
       or incoming.gross_amount_minor <= 0
       or incoming.accounting_gross_amount_minor <= 0
       or incoming.occurred_at is null
       or upper(incoming.currency_code) <> upper(asset_row.currency_code)
       or upper(incoming.accounting_currency_code) <> upper(system_wallet.currency_code)
       or (
            upper(incoming.currency_code) = upper(incoming.accounting_currency_code)
            and (
                incoming.gross_amount_minor <> incoming.accounting_gross_amount_minor
            )
       )
       or (
            upper(incoming.currency_code) <> upper(incoming.accounting_currency_code)
            and (
                coalesce(incoming.exchange_rate_decimal_string, '') = ''
                or incoming.exchange_rate_decimal_string::numeric <= 0
                or round(
                    incoming.gross_amount_minor::numeric
                    * incoming.exchange_rate_decimal_string::numeric
                )::bigint <> incoming.accounting_gross_amount_minor

            )
       ) then
        raise exception 'Invalid investment trade input';
    end if;

    if incoming.kind_raw_value = 'buy' then
        if incoming.funding_wallet_id is null or incoming.capital_return_wallet_id is not null then
            raise exception 'A buy requires one funding wallet';
        end if;
        select * into wallet_row from public.ledger_wallets
        where id = incoming.funding_wallet_id and user_id = incoming.user_id and deleted_at is null and is_archived = false;
    else
        if incoming.capital_return_wallet_id is null or incoming.funding_wallet_id is not null then
            raise exception 'A sale requires one capital return wallet';
        end if;
        select * into wallet_row from public.ledger_wallets
        where id = incoming.capital_return_wallet_id and user_id = incoming.user_id and deleted_at is null
          and is_archived = false and system_purpose_raw_value is null and kind_raw_value <> 'creditCard';
    end if;
    if wallet_row.id is null then raise exception 'Investment wallet selection is invalid'; end if;
    if not public.can_operate_wallet(wallet_row.id) then raise exception 'wallet.use is required'; end if;

    insert into public.investment_trades (
        id, user_id, channel_id, asset_id, kind_raw_value, quantity_decimal_string,
        gross_amount_minor, currency_code, accounting_gross_amount_minor,
        accounting_currency_code, exchange_rate_decimal_string,
        exchange_rate_provider, exchange_rate_date, funding_wallet_id, capital_return_wallet_id,
        funding_to_accounting_rate_decimal_string, accounting_to_capital_return_rate_decimal_string,
        note, occurred_at, created_at, updated_at, deleted_at, sync_version,
        last_modified_by_device_id
    ) values (
        incoming.id, incoming.user_id, incoming.channel_id, incoming.asset_id,
        incoming.kind_raw_value, incoming.quantity_decimal_string, incoming.gross_amount_minor,
        upper(incoming.currency_code), incoming.accounting_gross_amount_minor,
        upper(incoming.accounting_currency_code),
        incoming.exchange_rate_decimal_string, incoming.exchange_rate_provider,
        incoming.exchange_rate_date, incoming.funding_wallet_id, incoming.capital_return_wallet_id,
        incoming.funding_to_accounting_rate_decimal_string,
        incoming.accounting_to_capital_return_rate_decimal_string,
        nullif(btrim(incoming.note), ''), incoming.occurred_at,
        coalesce(incoming.created_at, now_value), now_value, null,
        case when existing.id is null then 1 else greatest(existing.sync_version + 1, coalesce(incoming.sync_version, 0)) end,
        incoming.last_modified_by_device_id
    ) on conflict (id) do update set
        channel_id = excluded.channel_id, asset_id = excluded.asset_id,
        kind_raw_value = excluded.kind_raw_value,
        quantity_decimal_string = excluded.quantity_decimal_string,
        gross_amount_minor = excluded.gross_amount_minor,
        currency_code = excluded.currency_code,
        accounting_gross_amount_minor = excluded.accounting_gross_amount_minor,
        accounting_currency_code = excluded.accounting_currency_code,
        exchange_rate_decimal_string = excluded.exchange_rate_decimal_string,
        exchange_rate_provider = excluded.exchange_rate_provider,
        exchange_rate_date = excluded.exchange_rate_date,
        funding_wallet_id = excluded.funding_wallet_id,
        capital_return_wallet_id = excluded.capital_return_wallet_id,
        funding_to_accounting_rate_decimal_string = excluded.funding_to_accounting_rate_decimal_string,
        accounting_to_capital_return_rate_decimal_string = excluded.accounting_to_capital_return_rate_decimal_string,
        note = excluded.note, occurred_at = excluded.occurred_at, updated_at = now_value,
        deleted_at = null, sync_version = excluded.sync_version,
        last_modified_by_device_id = excluded.last_modified_by_device_id;

    perform public.investment_rebuild_asset(
        incoming.user_id, incoming.asset_id, actor_id,
        incoming.last_modified_by_device_id, now_value
    );
    return query
    select * from public.investment_trades
    where user_id = incoming.user_id
      and asset_id = incoming.asset_id
      and deleted_at is null
    order by occurred_at, created_at, id;
end;
$$;

alter table public.investment_assets
    drop constraint if exists investment_assets_opening_quantity_check,
    drop constraint if exists investment_assets_opening_position_check,
    drop column symbol,
    drop column opening_quantity_decimal_string,
    drop column opening_cost_minor;

alter table public.investment_trades
    drop column fee_minor,
    drop column accounting_fee_minor;
