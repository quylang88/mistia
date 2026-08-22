-- Add free-form units to Investment inventory without breaking legacy rows or clients.
-- Existing unitless trades remain valid until an asset receives its first default unit.

alter table public.investment_assets
    add column if not exists default_unit_label text;

alter table public.investment_trades
    add column if not exists unit_label text;

alter table public.investment_assets
    drop constraint if exists investment_assets_default_unit_label_check,
    add constraint investment_assets_default_unit_label_check
        check (default_unit_label is null or nullif(btrim(default_unit_label), '') is not null);

alter table public.investment_trades
    drop constraint if exists investment_trades_unit_label_check,
    add constraint investment_trades_unit_label_check
        check (unit_label is null or nullif(btrim(unit_label), '') is not null);

create or replace function public.investment_normalize_unit_label(p_label text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
    select nullif(regexp_replace(btrim(p_label), '[[:space:]]+', ' ', 'g'), '')
$$;

create or replace function public.investment_unit_key(p_label text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
    select coalesce(lower(public.investment_normalize_unit_label(p_label)), '__mistia_legacy_unit__')
$$;

-- Keep the aggregate position snapshot for old clients while releasing FIFO lots
-- only from the unit selected by the sale.
do $migration$
declare
    function_definition text;
    old_fragment text;
    new_fragment text;
begin
    select pg_get_functiondef(
        'public.investment_rebuild_asset(uuid,uuid,uuid,uuid,timestamp with time zone)'::regprocedure
    ) into function_definition;

    old_fragment := $fragment$
    create temporary table if not exists pg_temp.investment_fifo_lots (
        lot_order bigint generated always as identity primary key,
        remaining_quantity numeric not null,
        remaining_cost bigint not null
    ) on commit drop;
    truncate table pg_temp.investment_fifo_lots;$fragment$;
    new_fragment := $fragment$
    drop table if exists pg_temp.investment_fifo_lots;
    create temporary table pg_temp.investment_fifo_lots (
        lot_order bigint generated always as identity primary key,
        unit_key text not null,
        remaining_quantity numeric not null,
        remaining_cost bigint not null
    ) on commit drop;$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'investment_rebuild_asset temp-lot fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
            insert into pg_temp.investment_fifo_lots (remaining_quantity, remaining_cost)
            values (trade_row.quantity_decimal_string::numeric, trade_row.accounting_gross_amount_minor);$fragment$;
    new_fragment := $fragment$
            insert into pg_temp.investment_fifo_lots (unit_key, remaining_quantity, remaining_cost)
            values (
                public.investment_unit_key(trade_row.unit_label),
                trade_row.quantity_decimal_string::numeric,
                trade_row.accounting_gross_amount_minor
            );$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'investment_rebuild_asset buy-lot fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
            if position_quantity < trade_row.quantity_decimal_string::numeric then
                raise exception 'Sale exceeds the quantity held';
            end if;$fragment$;
    new_fragment := $fragment$
            if coalesce((
                select sum(lot.remaining_quantity)
                from pg_temp.investment_fifo_lots lot
                where lot.unit_key = public.investment_unit_key(trade_row.unit_label)
            ), 0) < trade_row.quantity_decimal_string::numeric then
                raise exception 'Sale exceeds the quantity held for the selected unit';
            end if;$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'investment_rebuild_asset sale-capacity fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
                select lot_order, remaining_quantity, remaining_cost
                from pg_temp.investment_fifo_lots
                order by lot_order
                for update$fragment$;
    new_fragment := $fragment$
                select lot_order, remaining_quantity, remaining_cost
                from pg_temp.investment_fifo_lots
                where unit_key = public.investment_unit_key(trade_row.unit_label)
                order by lot_order
                for update$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'investment_rebuild_asset FIFO-select fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    execute function_definition;
end;
$migration$;

-- Extend the trade RPC while preserving fields sent by pre-unit app versions.
do $migration$
declare
    function_definition text;
    old_fragment text;
    new_fragment text;
begin
    select pg_get_functiondef(
        'public.mutate_investment_trade(jsonb,bigint,boolean)'::regprocedure
    ) into function_definition;

    old_fragment := $fragment$
    if asset_row.id is null then raise exception 'Investment asset/channel mismatch'; end if;$fragment$;
    new_fragment := $fragment$
    if asset_row.id is null then raise exception 'Investment asset/channel mismatch'; end if;

    if p_trade ? 'unit_label' then
        incoming.unit_label := public.investment_normalize_unit_label(incoming.unit_label);
    elsif existing.id is not null then
        incoming.unit_label := existing.unit_label;
    else
        incoming.unit_label := public.investment_normalize_unit_label(asset_row.default_unit_label);
    end if;$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_trade asset fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
        id, user_id, channel_id, asset_id, kind_raw_value, quantity_decimal_string,
        gross_amount_minor, currency_code, accounting_gross_amount_minor,$fragment$;
    new_fragment := $fragment$
        id, user_id, channel_id, asset_id, kind_raw_value, quantity_decimal_string, unit_label,
        gross_amount_minor, currency_code, accounting_gross_amount_minor,$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_trade insert-column fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
        incoming.kind_raw_value, incoming.quantity_decimal_string, incoming.gross_amount_minor,
        upper(incoming.currency_code), incoming.accounting_gross_amount_minor,$fragment$;
    new_fragment := $fragment$
        incoming.kind_raw_value, incoming.quantity_decimal_string, incoming.unit_label,
        incoming.gross_amount_minor, upper(incoming.currency_code), incoming.accounting_gross_amount_minor,$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_trade insert-value fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
        quantity_decimal_string = excluded.quantity_decimal_string,
        gross_amount_minor = excluded.gross_amount_minor,$fragment$;
    new_fragment := $fragment$
        quantity_decimal_string = excluded.quantity_decimal_string,
        unit_label = excluded.unit_label,
        gross_amount_minor = excluded.gross_amount_minor,$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_trade update fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    execute function_definition;
end;
$migration$;

-- Extend the atomic asset RPC. The first non-null default unit materializes all
-- unitless legacy trades at once, then rebuilds their derived snapshots.
do $migration$
declare
    function_definition text;
    old_fragment text;
    new_fragment text;
begin
    select pg_get_functiondef(
        'public.mutate_investment_asset(jsonb,bigint,boolean)'::regprocedure
    ) into function_definition;

    old_fragment := $fragment$
    select * into existing
    from public.investment_assets
    where id = incoming.id
    for update;$fragment$;
    new_fragment := $fragment$
    select * into existing
    from public.investment_assets
    where id = incoming.id
    for update;

    if p_asset ? 'default_unit_label' then
        incoming.default_unit_label := public.investment_normalize_unit_label(incoming.default_unit_label);
    elsif existing.id is not null then
        incoming.default_unit_label := existing.default_unit_label;
    end if;$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_asset existing-row fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
            id, user_id, channel_id, name, currency_code, image_path, sort_order,$fragment$;
    new_fragment := $fragment$
            id, user_id, channel_id, name, currency_code, image_path, default_unit_label, sort_order,$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_asset insert-column fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
            incoming.currency_code,
            incoming.image_path,
            coalesce(incoming.sort_order, 0),$fragment$;
    new_fragment := $fragment$
            incoming.currency_code,
            incoming.image_path,
            incoming.default_unit_label,
            coalesce(incoming.sort_order, 0),$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_asset insert-value fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
            image_path = incoming.image_path,
            sort_order = coalesce(incoming.sort_order, existing.sort_order),$fragment$;
    new_fragment := $fragment$
            image_path = incoming.image_path,
            default_unit_label = incoming.default_unit_label,
            sort_order = coalesce(incoming.sort_order, existing.sort_order),$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_asset update fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    old_fragment := $fragment$
    return query
    select * from public.investment_assets where id = incoming.id;$fragment$;
    new_fragment := $fragment$
    if existing.id is not null
       and existing.default_unit_label is null
       and incoming.default_unit_label is not null then
        update public.investment_trades
        set unit_label = incoming.default_unit_label,
            updated_at = now_value,
            sync_version = sync_version + 1,
            last_modified_by_device_id = incoming.last_modified_by_device_id
        where user_id = incoming.user_id
          and asset_id = incoming.id
          and unit_label is null;

        if exists (
            select 1 from public.investment_trades
            where user_id = incoming.user_id and asset_id = incoming.id and deleted_at is null
        ) then
            perform public.investment_rebuild_asset(
                incoming.user_id,
                incoming.id,
                actor_id,
                incoming.last_modified_by_device_id,
                now_value
            );
        end if;
    end if;

    return query
    select * from public.investment_assets where id = incoming.id;$fragment$;
    if strpos(function_definition, old_fragment) = 0 then
        raise exception 'mutate_investment_asset return fragment not found';
    end if;
    function_definition := replace(function_definition, old_fragment, new_fragment);

    execute function_definition;
end;
$migration$;

comment on column public.investment_assets.default_unit_label is
    'Owner-entered unit used to prefill new trades; the first value also resolves legacy unitless history.';
comment on column public.investment_trades.unit_label is
    'Owner-entered inventory unit. Nullable only for legacy and mixed-version compatibility.';
