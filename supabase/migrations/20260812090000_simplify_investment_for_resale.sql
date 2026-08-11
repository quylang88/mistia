-- Simplify Investment for small shops and resale activities.
-- Keep four domain tables, add private product images, and rebuild accounting with FIFO.

alter table public.investment_assets
    add column if not exists image_path text;

alter table public.investment_assets
    drop constraint if exists investment_assets_image_path_check;

alter table public.investment_assets
    add constraint investment_assets_image_path_check check (
        image_path is null
        or image_path ~ ('^' || lower(user_id::text) || '/' || lower(id::text) || '/[0-9a-f-]{36}\.jpg$')
    );

-- Patch the already-deployed rebuild function in-place so the ledger/posting
-- behavior stays identical while only the cost-release algorithm changes.
do $migration$
declare
    function_sql text;
    old_fragment text;
    new_fragment text;
begin
    select pg_get_functiondef(
        'public.investment_rebuild_asset(uuid,uuid,uuid,uuid,timestamp with time zone)'::regprocedure
    ) into function_sql;

    old_fragment := E'    keep_posting_ids uuid[];\nbegin';
    new_fragment := E'    keep_posting_ids uuid[];\n    quantity_to_release numeric;\n    lot_row record;\n    lot_release_quantity numeric;\n    lot_release_cost bigint;\nbegin';
    if position(old_fragment in function_sql) = 0 then
        raise exception 'Unable to locate investment FIFO declaration insertion point';
    end if;
    function_sql := replace(function_sql, old_fragment, new_fragment);

    old_fragment := E'    position_quantity := 0;\n    position_cost := 0;';
    new_fragment := E'    create temporary table if not exists pg_temp.investment_fifo_lots (\n        lot_order bigint generated always as identity primary key,\n        remaining_quantity numeric not null,\n        remaining_cost bigint not null\n    ) on commit drop;\n    truncate table pg_temp.investment_fifo_lots;\n\n    position_quantity := 0;\n    position_cost := 0;';
    if position(old_fragment in function_sql) = 0 then
        raise exception 'Unable to locate investment FIFO initialization point';
    end if;
    function_sql := replace(function_sql, old_fragment, new_fragment);

    old_fragment := E'            position_quantity := position_quantity + trade_row.quantity_decimal_string::numeric;\n            position_cost := position_cost + trade_row.accounting_gross_amount_minor;\n            funding_ledger_id := public.investment_ledger_id(trade_row.id, ''funding'');';
    new_fragment := E'            position_quantity := position_quantity + trade_row.quantity_decimal_string::numeric;\n            position_cost := position_cost + trade_row.accounting_gross_amount_minor;\n            insert into pg_temp.investment_fifo_lots (remaining_quantity, remaining_cost)\n            values (trade_row.quantity_decimal_string::numeric, trade_row.accounting_gross_amount_minor);\n            funding_ledger_id := public.investment_ledger_id(trade_row.id, ''funding'');';
    if position(old_fragment in function_sql) = 0 then
        raise exception 'Unable to locate investment FIFO buy insertion point';
    end if;
    function_sql := replace(function_sql, old_fragment, new_fragment);

    old_fragment := E'            if position_quantity = trade_row.quantity_decimal_string::numeric then\n                released_cost := position_cost;\n            else\n                released_cost := round(\n                    position_cost::numeric * trade_row.quantity_decimal_string::numeric / position_quantity\n                )::bigint;\n            end if;\n            realized_profit := trade_row.accounting_gross_amount_minor - released_cost;\n            position_quantity := position_quantity - trade_row.quantity_decimal_string::numeric;\n            position_cost := position_cost - released_cost;\n            if position_quantity = 0 then position_cost := 0; end if;';
    new_fragment := E'            quantity_to_release := trade_row.quantity_decimal_string::numeric;\n            released_cost := 0;\n            for lot_row in\n                select lot_order, remaining_quantity, remaining_cost\n                from pg_temp.investment_fifo_lots\n                order by lot_order\n                for update\n            loop\n                exit when quantity_to_release <= 0;\n                lot_release_quantity := least(quantity_to_release, lot_row.remaining_quantity);\n                if lot_release_quantity = lot_row.remaining_quantity then\n                    lot_release_cost := lot_row.remaining_cost;\n                else\n                    lot_release_cost := round(\n                        lot_row.remaining_cost::numeric\n                        * lot_release_quantity\n                        / lot_row.remaining_quantity\n                    )::bigint;\n                end if;\n                released_cost := released_cost + lot_release_cost;\n                quantity_to_release := quantity_to_release - lot_release_quantity;\n                if lot_release_quantity = lot_row.remaining_quantity then\n                    delete from pg_temp.investment_fifo_lots where lot_order = lot_row.lot_order;\n                else\n                    update pg_temp.investment_fifo_lots\n                    set remaining_quantity = remaining_quantity - lot_release_quantity,\n                        remaining_cost = remaining_cost - lot_release_cost\n                    where lot_order = lot_row.lot_order;\n                end if;\n            end loop;\n            if quantity_to_release > 0 then\n                raise exception ''Sale exceeds the quantity held'';\n            end if;\n            realized_profit := trade_row.accounting_gross_amount_minor - released_cost;\n            position_quantity := position_quantity - trade_row.quantity_decimal_string::numeric;\n            position_cost := position_cost - released_cost;\n            if position_quantity = 0 then position_cost := 0; end if;';
    if position(old_fragment in function_sql) = 0 then
        raise exception 'Unable to locate weighted-average investment release block';
    end if;
    function_sql := replace(function_sql, old_fragment, new_fragment);

    execute function_sql;
end;
$migration$;

-- Rebuild all current snapshots and their wallet/ledger derivatives under FIFO.
do $migration$
declare
    asset_row record;
    migration_now timestamptz := timezone('utc'::text, now());
begin
    for asset_row in
        select id, user_id from public.investment_assets order by user_id, id
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

drop trigger if exists investment_valuations_source_integrity on public.investment_valuations;
drop trigger if exists investment_valuations_set_updated_at on public.investment_valuations;
drop trigger if exists investment_channels_source_integrity on public.investment_channels;
drop trigger if exists investment_assets_source_integrity on public.investment_assets;

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
        if (
            tg_op = 'DELETE'
            or (tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null)
        ) and exists (
            select 1 from public.investment_trades trade where trade.asset_id = old.id
        ) then
            raise exception 'Investment products with history must be archived';
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

create trigger investment_channels_source_integrity
before insert or update or delete on public.investment_channels
for each row execute function public.enforce_investment_source_integrity();

create trigger investment_assets_source_integrity
before insert or update or delete on public.investment_assets
for each row execute function public.enforce_investment_source_integrity();

create or replace function public.family_resource_owner_user_id(p_resource_type text, p_resource_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare owner_id uuid;
begin
    if p_resource_id is null then return null; end if;
    case p_resource_type
        when 'wallet' then select user_id into owner_id from public.ledger_wallets where id = p_resource_id limit 1;
        when 'category' then select user_id into owner_id from public.transaction_categories where id = p_resource_id limit 1;
        when 'budget' then select user_id into owner_id from public.budget_plans where id = p_resource_id limit 1;
        when 'goal' then select user_id into owner_id from public.savings_goals where id = p_resource_id limit 1;
        when 'card' then select user_id into owner_id from public.credit_card_profiles where id = p_resource_id limit 1;
        when 'transaction' then select user_id into owner_id from public.ledger_transactions where id = p_resource_id limit 1;
        when 'bill' then select user_id into owner_id from public.recurring_bill_plans where id = p_resource_id limit 1;
        when 'due' then select user_id into owner_id from public.due_occurrence_records where id = p_resource_id limit 1;
        when 'installment' then select user_id into owner_id from public.installment_plans where id = p_resource_id limit 1;
        when 'event' then select user_id into owner_id from public.settlement_groups where id = p_resource_id limit 1;
        when 'investment' then
            select coalesce(
                (select user_id from public.investment_channels where id = p_resource_id limit 1),
                (select user_id from public.investment_assets where id = p_resource_id limit 1),
                (select user_id from public.investment_trades where id = p_resource_id limit 1)
            ) into owner_id;
        else owner_id := null;
    end case;
    return owner_id;
end;
$$;

-- Remove realtime publication dependency before dropping valuation storage.
do $$
begin
    if exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'investment_valuations'
    ) then
        alter publication supabase_realtime drop table public.investment_valuations;
    end if;
end;
$$;

drop table public.investment_valuations;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'investment-product-images',
    'investment-product-images',
    false,
    5242880,
    array['image/jpeg']
)
on conflict (id) do update set
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists investment_product_images_select on storage.objects;
drop policy if exists investment_product_images_insert on storage.objects;
drop policy if exists investment_product_images_update on storage.objects;
drop policy if exists investment_product_images_delete on storage.objects;

create policy investment_product_images_select
on storage.objects for select to authenticated
using (
    bucket_id = 'investment-product-images'
    and public.has_investment_permission((storage.foldername(name))[1]::uuid, 'view')
);

create policy investment_product_images_insert
on storage.objects for insert to authenticated
with check (
    bucket_id = 'investment-product-images'
    and (
        public.has_investment_permission((storage.foldername(name))[1]::uuid, 'create')
        or public.has_investment_permission((storage.foldername(name))[1]::uuid, 'edit')
    )
    and array_length(storage.foldername(name), 1) = 2
    and lower(storage.extension(name)) = 'jpg'
);

create policy investment_product_images_update
on storage.objects for update to authenticated
using (
    bucket_id = 'investment-product-images'
    and public.has_investment_permission((storage.foldername(name))[1]::uuid, 'edit')
)
with check (
    bucket_id = 'investment-product-images'
    and public.has_investment_permission((storage.foldername(name))[1]::uuid, 'edit')
);

create policy investment_product_images_delete
on storage.objects for delete to authenticated
using (
    bucket_id = 'investment-product-images'
    and public.has_investment_permission((storage.foldername(name))[1]::uuid, 'edit')
);

comment on column public.investment_assets.image_path is
    'Private Storage object path only; never a public URL or base64 payload.';
