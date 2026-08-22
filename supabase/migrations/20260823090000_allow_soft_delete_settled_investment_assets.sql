-- Keep completed FIFO history while allowing a settled product to be soft-deleted.
-- Products with remaining inventory must still be sold or settled first.

create or replace function public.enforce_investment_source_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    current_quantity numeric;
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
            select 1 from public.investment_assets asset where asset.channel_id = old.id
        ) then
            raise exception 'Investment channels with history must be archived';
        end if;
        if tg_op = 'UPDATE' and old.is_archived = false and new.is_archived = true and exists (
            select 1
            from public.investment_assets asset
            where asset.channel_id = old.id
              and asset.deleted_at is null
              and coalesce((
                  select trade.position_quantity_after_decimal_string::numeric
                  from public.investment_trades trade
                  where trade.asset_id = asset.id and trade.deleted_at is null
                  order by trade.occurred_at desc, trade.created_at desc, trade.id desc
                  limit 1
              ), 0) > 0
        ) then
            raise exception 'Sell all remaining stock before archiving the investment channel';
        end if;
    elsif tg_table_name = 'investment_assets' then
        if tg_op <> 'DELETE' and nullif(btrim(new.name), '') is null then
            raise exception 'Investment product name is required';
        end if;
        if tg_op = 'UPDATE' and exists (
            select 1 from public.investment_trades trade where trade.asset_id = old.id
        ) and (
            old.channel_id is distinct from new.channel_id
            or old.currency_code is distinct from new.currency_code
        ) then
            raise exception 'Product channel and currency are immutable after history exists';
        end if;
        if tg_op = 'DELETE' and exists (
            select 1 from public.investment_trades trade where trade.asset_id = old.id
        ) then
            raise exception 'Investment products with history cannot be permanently deleted';
        end if;
        if tg_op = 'UPDATE'
           and old.deleted_at is null
           and new.deleted_at is not null then
            select coalesce((
                select trade.position_quantity_after_decimal_string::numeric
                from public.investment_trades trade
                where trade.asset_id = old.id and trade.deleted_at is null
                order by trade.occurred_at desc, trade.created_at desc, trade.id desc
                limit 1
            ), 0) into current_quantity;
            if current_quantity > 0 then
                raise exception 'Sell all remaining stock before deleting the investment product';
            end if;
        end if;
        if tg_op = 'UPDATE' and old.is_archived = false and new.is_archived = true then
            select coalesce((
                select trade.position_quantity_after_decimal_string::numeric
                from public.investment_trades trade
                where trade.asset_id = old.id and trade.deleted_at is null
                order by trade.occurred_at desc, trade.created_at desc, trade.id desc
                limit 1
            ), 0) into current_quantity;
            if current_quantity > 0 then
                raise exception 'Sell all remaining stock before archiving the investment product';
            end if;
        end if;
    end if;

    if tg_op = 'DELETE' then return old; end if;
    return new;
end;
$$;
