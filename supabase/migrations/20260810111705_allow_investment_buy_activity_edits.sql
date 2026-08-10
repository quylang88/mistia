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
    original_asset_id uuid;
    first_asset_id uuid;
    second_asset_id uuid;
begin
    if actor_id is null then raise exception 'Not authenticated'; end if;
    incoming := jsonb_populate_record(null::public.investment_trades, p_trade);
    if incoming.id is null or incoming.user_id is null or incoming.asset_id is null or incoming.channel_id is null then
        raise exception 'Incomplete investment trade';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('investment-trade:' || incoming.id::text, 0));
    select * into existing from public.investment_trades where id = incoming.id;
    original_asset_id := coalesce(existing.asset_id, incoming.asset_id);
    if original_asset_id::text <= incoming.asset_id::text then
        first_asset_id := original_asset_id;
        second_asset_id := incoming.asset_id;
    else
        first_asset_id := incoming.asset_id;
        second_asset_id := original_asset_id;
    end if;
    perform pg_advisory_xact_lock(
        hashtextextended(lower(incoming.user_id::text || ':' || first_asset_id::text), 0)
    );
    if second_asset_id <> first_asset_id then
        perform pg_advisory_xact_lock(
            hashtextextended(lower(incoming.user_id::text || ':' || second_asset_id::text), 0)
        );
    end if;
    select * into existing from public.investment_trades where id = incoming.id for update;
    original_asset_id := coalesce(existing.asset_id, incoming.asset_id);

    required_scope := case when existing.id is null then 'create' else 'edit' end;
    if not public.has_investment_permission(incoming.user_id, required_scope) then
        raise exception 'Investment % permission is required', required_scope;
    end if;
    if existing.id is not null and existing.user_id <> incoming.user_id then
        raise exception 'Investment owner is immutable';
    end if;
    if existing.id is not null and existing.kind_raw_value <> incoming.kind_raw_value then
        raise exception 'Investment trade kind is immutable';
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
            and incoming.gross_amount_minor <> incoming.accounting_gross_amount_minor
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
        where id = incoming.funding_wallet_id
          and user_id = incoming.user_id
          and deleted_at is null
          and is_archived = false;
    else
        if incoming.capital_return_wallet_id is null or incoming.funding_wallet_id is not null then
            raise exception 'A sale requires one capital return wallet';
        end if;
        select * into wallet_row from public.ledger_wallets
        where id = incoming.capital_return_wallet_id
          and user_id = incoming.user_id
          and deleted_at is null
          and is_archived = false
          and system_purpose_raw_value is null
          and kind_raw_value <> 'creditCard';
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
        case when existing.id is null
            then 1
            else greatest(existing.sync_version + 1, coalesce(incoming.sync_version, 0))
        end,
        incoming.last_modified_by_device_id
    ) on conflict (id) do update set
        channel_id = excluded.channel_id,
        asset_id = excluded.asset_id,
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
        note = excluded.note,
        occurred_at = excluded.occurred_at,
        updated_at = now_value,
        deleted_at = null,
        sync_version = excluded.sync_version,
        last_modified_by_device_id = excluded.last_modified_by_device_id;

    if existing.id is not null and original_asset_id <> incoming.asset_id then
        perform public.investment_rebuild_asset(
            incoming.user_id,
            original_asset_id,
            actor_id,
            incoming.last_modified_by_device_id,
            now_value
        );
    end if;
    perform public.investment_rebuild_asset(
        incoming.user_id,
        incoming.asset_id,
        actor_id,
        incoming.last_modified_by_device_id,
        now_value
    );

    update public.investment_wallet_postings
    set asset_id = incoming.asset_id,
        updated_at = now_value,
        sync_version = sync_version + 1,
        last_modified_by_device_id = incoming.last_modified_by_device_id
    where user_id = incoming.user_id
      and trade_id = incoming.id
      and asset_id is distinct from incoming.asset_id;

    return query
    select * from public.investment_trades
    where user_id = incoming.user_id
      and deleted_at is null
      and asset_id in (original_asset_id, incoming.asset_id)
    order by occurred_at, created_at, id;
end;
$$;

revoke execute on function public.mutate_investment_trade(jsonb, bigint, boolean) from public, anon;
grant execute on function public.mutate_investment_trade(jsonb, bigint, boolean) to authenticated;
