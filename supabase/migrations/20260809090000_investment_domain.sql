-- Independent investment accounting domain, system Investment Wallet, and
-- owner-scoped family permissions. Investment source rows are separated from
-- ordinary cash-flow reporting; derived ledger rows are written by RPC only.

create extension if not exists pgcrypto with schema extensions;

alter table public.ledger_wallets
    add column if not exists system_purpose_raw_value text;

alter table public.ledger_wallets
    drop constraint if exists ledger_wallets_system_purpose_check,
    add constraint ledger_wallets_system_purpose_check
        check (system_purpose_raw_value is null or system_purpose_raw_value = 'investmentProfit');

create unique index if not exists ledger_wallets_owner_system_purpose_unique
    on public.ledger_wallets(user_id, system_purpose_raw_value)
    where system_purpose_raw_value is not null and deleted_at is null;

-- Destination wallets must use their snapshotted destination amount. This is
-- required for cross-currency Investment Wallet transfers and also repairs the
-- existing generic wallet balance snapshot path.
create or replace function public.mistia_calculate_wallet_current_balance(
  p_wallet_id uuid,
  p_user_id uuid,
  p_wallet_kind text,
  p_opening_balance_minor bigint
)
returns bigint
language sql
stable
as $$
  with raw_balance as (
    select
      case when p_wallet_kind = 'creditCard' then 0 else p_opening_balance_minor end
      + coalesce(
        (
          select sum(
            case
              when tx.source_wallet_id = p_wallet_id then
                public.mistia_wallet_balance_delta(
                  p_wallet_kind,
                  tx.primary_kind_raw_value,
                  tx.transfer_subtype_raw_value,
                  tx.debt_intent_raw_value,
                  tx.amount_minor,
                  'source'
                )
              else 0
            end
            +
            case
              when tx.destination_wallet_id = p_wallet_id then
                public.mistia_wallet_balance_delta(
                  p_wallet_kind,
                  tx.primary_kind_raw_value,
                  tx.transfer_subtype_raw_value,
                  tx.debt_intent_raw_value,
                  coalesce(tx.destination_amount_minor, tx.amount_minor),
                  'destination'
                )
              else 0
            end
          )
          from public.ledger_transactions tx
          where tx.user_id = p_user_id
            and tx.deleted_at is null
            and coalesce(tx.is_archived, false) = false
            and tx.entry_status_raw_value = 'posted'
            and (tx.source_wallet_id = p_wallet_id or tx.destination_wallet_id = p_wallet_id)
        ),
        0
      ) as balance_minor
  ),
  credit_profile as (
    select coalesce(profile.credit_limit_minor, 0) as credit_limit_minor
    from public.credit_card_profiles profile
    where profile.wallet_id = p_wallet_id
      and profile.user_id = p_user_id
      and profile.deleted_at is null
    order by profile.updated_at desc
    limit 1
  )
  select case
    when p_wallet_kind = 'creditCard' then
      greatest(
        coalesce((select credit_limit_minor from credit_profile), 0)
          - greatest((select balance_minor from raw_balance), 0),
        0
      )
    else (select balance_minor from raw_balance)
  end;
$$;

update public.ledger_wallets wallet
set current_balance_minor = public.mistia_calculate_wallet_current_balance(
  wallet.id,
  wallet.user_id,
  wallet.kind_raw_value,
  wallet.opening_balance_minor
)
where wallet.current_balance_minor is distinct from public.mistia_calculate_wallet_current_balance(
  wallet.id,
  wallet.user_id,
  wallet.kind_raw_value,
  wallet.opening_balance_minor
);

create table if not exists public.investment_channels (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    icon_symbol_name text not null default 'chart.line.uptrend.xyaxis',
    icon_color_hex text not null default '#9A67FF',
    sort_order integer not null default 0,
    is_archived boolean not null default false,
    archived_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    deleted_at timestamptz,
    sync_version bigint not null default 1,
    last_modified_by_device_id uuid
);

create table if not exists public.investment_assets (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    channel_id uuid not null references public.investment_channels(id) on delete restrict,
    name text not null,
    symbol text,
    currency_code text not null,
    opening_quantity_decimal_string text not null default '0',
    opening_cost_minor bigint not null default 0 check (opening_cost_minor >= 0),
    sort_order integer not null default 0,
    is_archived boolean not null default false,
    archived_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    deleted_at timestamptz,
    sync_version bigint not null default 1,
    last_modified_by_device_id uuid,
    constraint investment_assets_opening_quantity_check
        check ((opening_quantity_decimal_string)::numeric >= 0),
    constraint investment_assets_opening_position_check
        check ((opening_quantity_decimal_string)::numeric > 0 or opening_cost_minor = 0)
);

create table if not exists public.investment_trades (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    channel_id uuid not null references public.investment_channels(id) on delete restrict,
    asset_id uuid not null references public.investment_assets(id) on delete restrict,
    kind_raw_value text not null check (kind_raw_value in ('buy', 'sell')),
    quantity_decimal_string text not null,
    gross_amount_minor bigint not null check (gross_amount_minor > 0),
    fee_minor bigint not null default 0 check (fee_minor >= 0),
    currency_code text not null,
    accounting_gross_amount_minor bigint not null check (accounting_gross_amount_minor > 0),
    accounting_fee_minor bigint not null default 0 check (accounting_fee_minor >= 0),
    accounting_currency_code text not null,
    exchange_rate_decimal_string text,
    exchange_rate_provider text,
    exchange_rate_date text,
    funding_wallet_id uuid references public.ledger_wallets(id) on delete restrict,
    capital_return_wallet_id uuid references public.ledger_wallets(id) on delete restrict,
    funding_wallet_currency_code text,
    capital_return_wallet_currency_code text,
    funding_wallet_amount_minor bigint,
    capital_return_wallet_amount_minor bigint,
    funding_to_accounting_rate_decimal_string text,
    accounting_to_capital_return_rate_decimal_string text,
    funding_ledger_transaction_id uuid references public.ledger_transactions(id) on delete set null,
    capital_return_ledger_transaction_id uuid references public.ledger_transactions(id) on delete set null,
    profit_loss_ledger_transaction_id uuid references public.ledger_transactions(id) on delete set null,
    released_cost_basis_minor bigint not null default 0,
    realized_profit_loss_minor bigint not null default 0,
    position_quantity_after_decimal_string text not null default '0',
    position_cost_basis_after_minor bigint not null default 0,
    note text,
    occurred_at timestamptz not null,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    deleted_at timestamptz,
    sync_version bigint not null default 1,
    last_modified_by_device_id uuid,
    constraint investment_trades_quantity_check check ((quantity_decimal_string)::numeric > 0),
    constraint investment_trades_position_quantity_check check ((position_quantity_after_decimal_string)::numeric >= 0),
    constraint investment_trades_position_cost_check check (position_cost_basis_after_minor >= 0),
    constraint investment_trades_wallet_shape_check check (
        (kind_raw_value = 'buy' and funding_wallet_id is not null and capital_return_wallet_id is null)
        or (kind_raw_value = 'sell' and funding_wallet_id is null and capital_return_wallet_id is not null)
    )
);

create table if not exists public.investment_valuations (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    channel_id uuid not null references public.investment_channels(id) on delete restrict,
    asset_id uuid not null references public.investment_assets(id) on delete restrict,
    market_value_minor bigint not null check (market_value_minor >= 0),
    accounting_market_value_minor bigint not null check (accounting_market_value_minor >= 0),
    currency_code text not null,
    accounting_currency_code text not null,
    exchange_rate_decimal_string text,
    valued_at timestamptz not null,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    deleted_at timestamptz,
    sync_version bigint not null default 1,
    last_modified_by_device_id uuid
);

create table if not exists public.investment_wallet_postings (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    event_id uuid not null,
    trade_id uuid references public.investment_trades(id) on delete restrict,
    asset_id uuid references public.investment_assets(id) on delete restrict,
    wallet_id uuid not null references public.ledger_wallets(id) on delete restrict,
    ledger_transaction_id uuid not null references public.ledger_transactions(id) on delete restrict,
    role_raw_value text not null check (role_raw_value in ('funding', 'capitalReturn', 'realizedProfit', 'transferOut', 'transferIn')),
    amount_minor bigint not null,
    currency_code text not null,
    accounting_amount_minor bigint not null,
    accounting_currency_code text not null,
    occurred_at timestamptz not null,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    deleted_at timestamptz,
    sync_version bigint not null default 1,
    last_modified_by_device_id uuid
);

create index if not exists investment_channels_owner_updated_idx on public.investment_channels(user_id, updated_at desc);
create index if not exists investment_assets_owner_channel_idx on public.investment_assets(user_id, channel_id, updated_at desc);
create index if not exists investment_trades_asset_order_idx on public.investment_trades(user_id, asset_id, occurred_at, created_at, id) where deleted_at is null;
create index if not exists investment_trades_owner_occurred_idx on public.investment_trades(user_id, occurred_at desc);
create index if not exists investment_valuations_asset_date_idx on public.investment_valuations(user_id, asset_id, valued_at desc);
create index if not exists investment_postings_owner_date_idx on public.investment_wallet_postings(user_id, occurred_at desc);
create index if not exists investment_postings_trade_idx on public.investment_wallet_postings(trade_id) where trade_id is not null;

drop trigger if exists investment_channels_set_updated_at on public.investment_channels;
create trigger investment_channels_set_updated_at before update on public.investment_channels
for each row execute function public.set_updated_at();
drop trigger if exists investment_assets_set_updated_at on public.investment_assets;
create trigger investment_assets_set_updated_at before update on public.investment_assets
for each row execute function public.set_updated_at();
drop trigger if exists investment_valuations_set_updated_at on public.investment_valuations;
create trigger investment_valuations_set_updated_at before update on public.investment_valuations
for each row execute function public.set_updated_at();

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
                  asset.opening_quantity_decimal_string::numeric
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
            or old.opening_quantity_decimal_string is distinct from new.opening_quantity_decimal_string
            or old.opening_cost_minor is distinct from new.opening_cost_minor
        ) then
            raise exception 'Asset channel, currency and opening position are immutable after history exists';
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
                old.opening_quantity_decimal_string::numeric
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

drop trigger if exists investment_channels_source_integrity on public.investment_channels;
create trigger investment_channels_source_integrity
before insert or update or delete on public.investment_channels
for each row execute function public.enforce_investment_source_integrity();
drop trigger if exists investment_assets_source_integrity on public.investment_assets;
create trigger investment_assets_source_integrity
before insert or update or delete on public.investment_assets
for each row execute function public.enforce_investment_source_integrity();
drop trigger if exists investment_valuations_source_integrity on public.investment_valuations;
create trigger investment_valuations_source_integrity
before insert or update or delete on public.investment_valuations
for each row execute function public.enforce_investment_source_integrity();

alter table public.family_permission_grants
    drop constraint if exists family_permission_grants_resource_type_check,
    add constraint family_permission_grants_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer', 'event', 'investment'));
alter table public.family_permission_requests
    drop constraint if exists family_permission_requests_resource_type_check,
    add constraint family_permission_requests_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer', 'event', 'investment'));
alter table public.family_notifications
    drop constraint if exists family_notifications_resource_type_check,
    add constraint family_notifications_resource_type_check
        check (resource_type is null or resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer', 'event', 'investment'));

create or replace function public.has_investment_permission(p_owner_user_id uuid, p_scope text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        (select auth.uid()) = p_owner_user_id
        or (
            public.has_family_permission_grant(p_owner_user_id, 'investment', null, 'view')
            and (
                p_scope = 'view'
                or (p_scope = 'create' and public.has_family_permission_grant(p_owner_user_id, 'investment', null, 'create'))
                or (p_scope = 'edit' and public.has_family_permission_grant(p_owner_user_id, 'investment', null, 'edit'))
            )
        );
$$;

revoke execute on function public.has_investment_permission(uuid, text) from public, anon;
grant execute on function public.has_investment_permission(uuid, text) to authenticated;

create or replace function public.enforce_investment_permission_dependencies()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.resource_type <> 'investment' then
        return new;
    end if;
    if (select auth.uid()) is distinct from new.owner_user_id then
        raise exception 'Only the investment owner can grant or revoke investment permission';
    end if;
    if new.permission_scope in ('create', 'edit') and new.revoked_at is null and not exists (
        select 1 from public.family_permission_grants view_grant
        where view_grant.family_id = new.family_id
          and view_grant.grantee_user_id = new.grantee_user_id
          and view_grant.owner_user_id = new.owner_user_id
          and view_grant.resource_type = 'investment'
          and view_grant.resource_id is null
          and view_grant.permission_scope = 'view'
          and view_grant.revoked_at is null
    ) then
        raise exception 'Investment create/edit permission requires active view permission';
    end if;
    return new;
end;
$$;

drop trigger if exists family_permission_grants_investment_dependency on public.family_permission_grants;
create trigger family_permission_grants_investment_dependency
before insert or update on public.family_permission_grants
for each row execute function public.enforce_investment_permission_dependencies();

create or replace function public.revoke_dependent_investment_permissions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.resource_type = 'investment'
       and new.permission_scope = 'view'
       and old.revoked_at is null
       and new.revoked_at is not null then
        update public.family_permission_grants
        set revoked_at = new.revoked_at,
            updated_at = new.updated_at
        where family_id = new.family_id
          and grantee_user_id = new.grantee_user_id
          and owner_user_id = new.owner_user_id
          and resource_type = 'investment'
          and resource_id is null
          and permission_scope in ('create', 'edit')
          and revoked_at is null;
    end if;
    return null;
end;
$$;

drop trigger if exists family_permission_grants_revoke_investment_dependents on public.family_permission_grants;
create trigger family_permission_grants_revoke_investment_dependents
after update on public.family_permission_grants
for each row execute function public.revoke_dependent_investment_permissions();

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
                (select user_id from public.investment_trades where id = p_resource_id limit 1),
                (select user_id from public.investment_valuations where id = p_resource_id limit 1)
            ) into owner_id;
        else owner_id := null;
    end case;
    return owner_id;
end;
$$;

alter table public.investment_channels enable row level security;
alter table public.investment_assets enable row level security;
alter table public.investment_trades enable row level security;
alter table public.investment_valuations enable row level security;
alter table public.investment_wallet_postings enable row level security;

grant select, insert, update, delete on table public.investment_channels to authenticated;
grant select, insert, update, delete on table public.investment_assets to authenticated;
grant select on table public.investment_trades to authenticated;
grant select, insert, update, delete on table public.investment_valuations to authenticated;
grant select on table public.investment_wallet_postings to authenticated;

create policy investment_channels_select on public.investment_channels for select to authenticated
using (public.has_investment_permission(user_id, 'view'));
create policy investment_channels_insert on public.investment_channels for insert to authenticated
with check (
    public.has_investment_permission(user_id, 'create')
    and exists (
        select 1 from public.ledger_wallets wallet
        where wallet.user_id = user_id
          and wallet.system_purpose_raw_value = 'investmentProfit'
          and wallet.deleted_at is null
    )
);
create policy investment_channels_update on public.investment_channels for update to authenticated
using (public.has_investment_permission(user_id, 'edit'))
with check (public.has_investment_permission(user_id, 'edit'));
create policy investment_channels_delete on public.investment_channels for delete to authenticated
using (public.has_investment_permission(user_id, 'edit'));

create policy investment_assets_select on public.investment_assets for select to authenticated
using (public.has_investment_permission(user_id, 'view'));
create policy investment_assets_insert on public.investment_assets for insert to authenticated
with check (
    public.has_investment_permission(user_id, 'create')
    and exists (select 1 from public.investment_channels c where c.id = channel_id and c.user_id = user_id and c.deleted_at is null)
);
create policy investment_assets_update on public.investment_assets for update to authenticated
using (public.has_investment_permission(user_id, 'edit'))
with check (
    public.has_investment_permission(user_id, 'edit')
    and exists (select 1 from public.investment_channels c where c.id = channel_id and c.user_id = user_id)
);
create policy investment_assets_delete on public.investment_assets for delete to authenticated
using (public.has_investment_permission(user_id, 'edit'));

create policy investment_trades_select on public.investment_trades for select to authenticated
using (public.has_investment_permission(user_id, 'view'));

create policy investment_valuations_select on public.investment_valuations for select to authenticated
using (public.has_investment_permission(user_id, 'view'));
create policy investment_valuations_insert on public.investment_valuations for insert to authenticated
with check (
    public.has_investment_permission(user_id, 'create')
    and exists (select 1 from public.investment_assets a where a.id = asset_id and a.channel_id = channel_id and a.user_id = user_id and a.deleted_at is null)
);
create policy investment_valuations_update on public.investment_valuations for update to authenticated
using (public.has_investment_permission(user_id, 'edit'))
with check (
    public.has_investment_permission(user_id, 'edit')
    and exists (select 1 from public.investment_assets a where a.id = asset_id and a.channel_id = channel_id and a.user_id = user_id)
);
create policy investment_valuations_delete on public.investment_valuations for delete to authenticated
using (public.has_investment_permission(user_id, 'edit'));

create policy investment_postings_select on public.investment_wallet_postings for select to authenticated
using (public.has_investment_permission(user_id, 'view'));

-- Existing broad family policies remain in place, but these restrictive gates
-- prevent investment wallets and derived transactions from leaking through them.
drop policy if exists investment_system_wallet_privacy_gate on public.ledger_wallets;
create policy investment_system_wallet_privacy_gate
on public.ledger_wallets as restrictive for select to authenticated
using (
    system_purpose_raw_value is null
    or public.has_investment_permission(user_id, 'view')
);

drop policy if exists investment_system_wallet_select on public.ledger_wallets;
create policy investment_system_wallet_select
on public.ledger_wallets for select to authenticated
using (
    system_purpose_raw_value = 'investmentProfit'
    and public.has_investment_permission(user_id, 'view')
);

drop policy if exists investment_ledger_privacy_gate on public.ledger_transactions;
create policy investment_ledger_privacy_gate
on public.ledger_transactions as restrictive for select to authenticated
using (
    settlement_role_raw_value is null
    or settlement_role_raw_value not like 'investment%'
    or public.has_investment_permission(user_id, 'view')
);

drop policy if exists investment_ledger_select on public.ledger_transactions;
create policy investment_ledger_select
on public.ledger_transactions for select to authenticated
using (
    settlement_role_raw_value like 'investment%'
    and public.has_investment_permission(user_id, 'view')
);

create or replace function public.mistia_deterministic_uuid(p_seed text)
returns uuid
language plpgsql
immutable
strict
as $$
declare
    bytes bytea := substring(extensions.digest(p_seed, 'sha256') for 16);
    hex text;
begin
    bytes := set_byte(bytes, 6, (get_byte(bytes, 6) & 15) | 80);
    bytes := set_byte(bytes, 8, (get_byte(bytes, 8) & 63) | 128);
    hex := encode(bytes, 'hex');
    return (substring(hex, 1, 8) || '-' || substring(hex, 9, 4) || '-' || substring(hex, 13, 4)
        || '-' || substring(hex, 17, 4) || '-' || substring(hex, 21, 12))::uuid;
end;
$$;

create or replace function public.investment_system_wallet_id(p_owner_user_id uuid)
returns uuid
language sql
immutable
strict
as $$
    select public.mistia_deterministic_uuid('com.mistia.wallet.system.investment-profit:' || lower(p_owner_user_id::text));
$$;

create or replace function public.investment_ledger_id(p_event_id uuid, p_component text)
returns uuid
language sql
immutable
strict
as $$
    select public.mistia_deterministic_uuid('com.mistia.investment.ledger:' || lower(p_event_id::text) || ':' || p_component);
$$;

drop policy if exists investment_system_wallet_insert on public.ledger_wallets;
create policy investment_system_wallet_insert
on public.ledger_wallets for insert to authenticated
with check (
    system_purpose_raw_value = 'investmentProfit'
    and id = public.investment_system_wallet_id(user_id)
    and public.has_investment_permission(user_id, 'create')
);

create or replace function public.enforce_investment_system_wallet()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'DELETE' and old.system_purpose_raw_value = 'investmentProfit' then
        raise exception 'The system Investment Wallet cannot be deleted';
    end if;
    if tg_op = 'DELETE' then return old; end if;

    if new.system_purpose_raw_value = 'investmentProfit' then
        if new.id <> public.investment_system_wallet_id(new.user_id) then
            raise exception 'Invalid system Investment Wallet identity';
        end if;
        if tg_op = 'INSERT' and not public.has_investment_permission(new.user_id, 'create') then
            raise exception 'Investment create permission is required';
        end if;
        if tg_op = 'UPDATE' and (
            old.user_id is distinct from new.user_id
            or old.currency_code is distinct from new.currency_code
            or old.system_purpose_raw_value is distinct from new.system_purpose_raw_value
        ) then
            raise exception 'System Investment Wallet owner, purpose and currency are immutable';
        end if;
        new.name := 'Investment Wallet';
        new.kind_raw_value := 'investment';
        new.icon_symbol_name := 'chart.line.uptrend.xyaxis';
        new.icon_color_hex := '#9A67FF';
        new.opening_balance_minor := 0;
        new.institution_display_name := null;
        new.institution_preset_key := null;
        new.sort_order := 2147483547;
        new.is_archived := false;
        new.archived_at := null;
        new.deleted_at := null;
    elsif tg_op = 'UPDATE' and old.system_purpose_raw_value = 'investmentProfit' then
        raise exception 'System Investment Wallet purpose is immutable';
    end if;
    return new;
end;
$$;

drop trigger if exists ledger_wallets_enforce_investment_system_wallet on public.ledger_wallets;
create trigger ledger_wallets_enforce_investment_system_wallet
before insert or update or delete on public.ledger_wallets
for each row execute function public.enforce_investment_system_wallet();

-- Only investment View may operate the system wallet, and Create is required
-- for outbound transfers or using positive retained profit for a new buy.
create or replace function public.can_operate_wallet(target_wallet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.ledger_wallets w
        where w.id = target_wallet_id
          and (
              (w.system_purpose_raw_value is null and public.has_family_permission_grant(w.user_id, 'wallet', w.id, 'use'))
              or (w.system_purpose_raw_value = 'investmentProfit' and public.has_investment_permission(w.user_id, 'create'))
          )
    );
$$;

revoke execute on function public.can_operate_wallet(uuid) from public, anon;
grant execute on function public.can_operate_wallet(uuid) to authenticated;

create or replace function public.create_family_permission_request(
    p_family_id uuid,
    p_recipient_user_id uuid,
    p_resource_type text,
    p_resource_id uuid,
    p_permission_scope text,
    p_title text,
    p_body text,
    p_message text default null
)
returns public.family_permission_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_id uuid := auth.uid();
    owner_id uuid;
    request_row public.family_permission_requests;
begin
    if requester_id is null then raise exception 'Not authenticated'; end if;
    if requester_id = p_recipient_user_id then raise exception 'Cannot request permission from yourself'; end if;
    if p_permission_scope not in ('use', 'edit', 'create', 'view') then raise exception 'Unsupported permission scope'; end if;
    if p_resource_type not in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer', 'event', 'investment') then
        raise exception 'Unsupported permission resource type';
    end if;
    if p_resource_type = 'wallet' and p_permission_scope in ('use', 'edit') and p_resource_id is null then
        raise exception 'Wallet use/edit requests require a wallet';
    end if;
    if p_resource_type = 'investment' and (p_resource_id is not null or p_permission_scope = 'use') then
        raise exception 'Investment permissions are owner-scoped and support view/create/edit only';
    end if;
    if not public.active_family_member_exists(p_family_id, requester_id)
       or not public.active_family_member_exists(p_family_id, p_recipient_user_id) then
        raise exception 'Both users must be active family members';
    end if;
    if p_resource_type = 'category' and p_permission_scope = 'use' and (
        not public.user_has_synced_finance_data(requester_id)
        or not public.user_has_synced_finance_data(p_recipient_user_id)
    ) then
        raise exception 'Both users must sync data to cloud before requesting a system category';
    end if;
    owner_id := public.family_resource_owner_user_id(p_resource_type, p_resource_id);
    if owner_id is not null and owner_id <> p_recipient_user_id then raise exception 'Recipient does not own this resource'; end if;

    select * into request_row
    from public.family_permission_requests fpr
    where fpr.family_id = p_family_id
      and fpr.requester_user_id = requester_id
      and fpr.recipient_user_id = p_recipient_user_id
      and fpr.resource_type = p_resource_type
      and fpr.resource_id is not distinct from p_resource_id
      and fpr.permission_scope = p_permission_scope
      and fpr.status = 'pending'
    for update;

    if request_row.id is null then
        insert into public.family_permission_requests (
            family_id, requester_user_id, recipient_user_id, resource_type,
            resource_id, permission_scope, message
        ) values (
            p_family_id, requester_id, p_recipient_user_id, p_resource_type,
            p_resource_id, p_permission_scope, p_message
        ) returning * into request_row;
    else
        update public.family_permission_requests
        set updated_at = timezone('utc'::text, now()), message = p_message
        where id = request_row.id returning * into request_row;
    end if;

    insert into public.family_notifications (
        source_event_key, family_id, user_id, actor_user_id, kind, resource_type,
        resource_id, permission_scope, permission_request_id, action_state,
        title, body, metadata
    ) values (
        'permission-request:' || request_row.id::text,
        p_family_id, p_recipient_user_id, requester_id,
        'permission_request_received', p_resource_type, p_resource_id,
        p_permission_scope, request_row.id, 'pending',
        coalesce(nullif(p_title, ''), 'New permission request'),
        coalesce(nullif(p_body, ''), 'A family member requested access to your data.'),
        jsonb_build_object('request_id', request_row.id)
    ) on conflict (source_event_key) do update set
        updated_at = timezone('utc'::text, now()), action_state = 'pending', read_at = null;

    return request_row;
end;
$$;

revoke execute on function public.create_family_permission_request(uuid, uuid, text, uuid, text, text, text, text) from public, anon;
grant execute on function public.create_family_permission_request(uuid, uuid, text, uuid, text, text, text, text) to authenticated;

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

    position_quantity := asset_row.opening_quantity_decimal_string::numeric;
    position_cost := asset_row.opening_cost_minor;

    for trade_row in
        select * from public.investment_trades
        where user_id = p_owner_user_id and asset_id = p_asset_id and deleted_at is null
        order by occurred_at, created_at, id
        for update
    loop
        if trade_row.quantity_decimal_string::numeric <= 0
           or trade_row.accounting_gross_amount_minor <= 0
           or trade_row.accounting_fee_minor < 0
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
                funding_amount := trade_row.accounting_gross_amount_minor + trade_row.accounting_fee_minor;
            else
                if coalesce(trade_row.funding_to_accounting_rate_decimal_string, '') = ''
                   or trade_row.funding_to_accounting_rate_decimal_string::numeric <= 0 then
                    raise exception 'Funding exchange-rate snapshot is required';
                end if;
                funding_amount := round(
                    (trade_row.accounting_gross_amount_minor + trade_row.accounting_fee_minor)::numeric
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
            position_cost := position_cost + trade_row.accounting_gross_amount_minor + trade_row.accounting_fee_minor;
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
                trade_row.accounting_gross_amount_minor + trade_row.accounting_fee_minor,
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
                -(trade_row.accounting_gross_amount_minor + trade_row.accounting_fee_minor),
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
            realized_profit := trade_row.accounting_gross_amount_minor - trade_row.accounting_fee_minor - released_cost;
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
       or incoming.fee_minor < 0
       or incoming.accounting_fee_minor < 0
       or incoming.occurred_at is null
       or upper(incoming.currency_code) <> upper(asset_row.currency_code)
       or upper(incoming.accounting_currency_code) <> upper(system_wallet.currency_code)
       or (
            upper(incoming.currency_code) = upper(incoming.accounting_currency_code)
            and (
                incoming.gross_amount_minor <> incoming.accounting_gross_amount_minor
                or incoming.fee_minor <> incoming.accounting_fee_minor
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
                or round(
                    incoming.fee_minor::numeric
                    * incoming.exchange_rate_decimal_string::numeric
                )::bigint <> incoming.accounting_fee_minor
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
        gross_amount_minor, fee_minor, currency_code, accounting_gross_amount_minor,
        accounting_fee_minor, accounting_currency_code, exchange_rate_decimal_string,
        exchange_rate_provider, exchange_rate_date, funding_wallet_id, capital_return_wallet_id,
        funding_to_accounting_rate_decimal_string, accounting_to_capital_return_rate_decimal_string,
        note, occurred_at, created_at, updated_at, deleted_at, sync_version,
        last_modified_by_device_id
    ) values (
        incoming.id, incoming.user_id, incoming.channel_id, incoming.asset_id,
        incoming.kind_raw_value, incoming.quantity_decimal_string, incoming.gross_amount_minor,
        incoming.fee_minor, upper(incoming.currency_code), incoming.accounting_gross_amount_minor,
        incoming.accounting_fee_minor, upper(incoming.accounting_currency_code),
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
        gross_amount_minor = excluded.gross_amount_minor, fee_minor = excluded.fee_minor,
        currency_code = excluded.currency_code,
        accounting_gross_amount_minor = excluded.accounting_gross_amount_minor,
        accounting_fee_minor = excluded.accounting_fee_minor,
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

create or replace function public.delete_investment_trade(
    p_trade_id uuid,
    p_owner_user_id uuid,
    p_expected_version bigint,
    p_modified_at timestamptz,
    p_device_id uuid
)
returns setof public.investment_trades
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    trade_row public.investment_trades%rowtype;
begin
    if actor_id is null then raise exception 'Not authenticated'; end if;
    if not public.has_investment_permission(p_owner_user_id, 'edit') then raise exception 'Investment edit permission is required'; end if;
    select * into trade_row from public.investment_trades
    where id = p_trade_id and user_id = p_owner_user_id;
    if trade_row.id is null then return; end if;
    perform pg_advisory_xact_lock(hashtextextended(lower(p_owner_user_id::text || ':' || trade_row.asset_id::text), 0));
    select * into trade_row from public.investment_trades
    where id = p_trade_id and user_id = p_owner_user_id for update;
    if trade_row.id is null or trade_row.sync_version <> p_expected_version then return; end if;

    update public.investment_trades
    set deleted_at = p_modified_at, updated_at = p_modified_at,
        sync_version = sync_version + 1, last_modified_by_device_id = p_device_id
    where id = p_trade_id;
    perform public.investment_rebuild_asset(
        p_owner_user_id, trade_row.asset_id, actor_id, p_device_id, p_modified_at
    );
    return query select * from public.investment_trades where id = p_trade_id;
end;
$$;

revoke execute on function public.mutate_investment_trade(jsonb, bigint, boolean) from public, anon;
grant execute on function public.mutate_investment_trade(jsonb, bigint, boolean) to authenticated;
revoke execute on function public.delete_investment_trade(uuid, uuid, bigint, timestamptz, uuid) from public, anon;
grant execute on function public.delete_investment_trade(uuid, uuid, bigint, timestamptz, uuid) to authenticated;

create or replace function public.enforce_investment_transfer_invariants()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    source_wallet public.ledger_wallets%rowtype;
    destination_wallet public.ledger_wallets%rowtype;
    available_source_balance bigint;
begin
    if new.settlement_role_raw_value is distinct from 'investmentTransfer' then
        return new;
    end if;
    if new.deleted_at is not null then
        return new;
    end if;

    select * into source_wallet
    from public.ledger_wallets
    where id = new.source_wallet_id and user_id = new.user_id and deleted_at is null
    for update;
    select * into destination_wallet
    from public.ledger_wallets
    where id = new.destination_wallet_id and user_id = new.user_id and deleted_at is null
    for update;

    if source_wallet.system_purpose_raw_value is distinct from 'investmentProfit'
       or source_wallet.id <> public.investment_system_wallet_id(new.user_id)
       or destination_wallet.id is null
       or destination_wallet.system_purpose_raw_value is not null
       or destination_wallet.kind_raw_value = 'creditCard'
       or destination_wallet.is_archived
       or new.destination_wallet_id = new.source_wallet_id
       or new.primary_kind_raw_value <> 'transfer'
       or new.transfer_subtype_raw_value <> 'internalTransfer'
       or new.entry_status_raw_value <> 'posted'
       or coalesce(new.is_archived, false)
       or new.category_id is not null
       or coalesce(new.reporting_expense_minor, 0) <> 0
       or coalesce(new.reporting_income_minor, 0) <> 0
       or new.amount_minor <= 0
       or coalesce(new.destination_amount_minor, new.amount_minor) <= 0
       or upper(coalesce(new.source_currency_code, '')) <> upper(source_wallet.currency_code)
       or upper(coalesce(new.destination_currency_code, '')) <> upper(destination_wallet.currency_code)
       or upper(coalesce(new.reporting_currency_code, '')) <> upper(source_wallet.currency_code)
       or new.reporting_amount_minor is distinct from new.amount_minor
       or (
            upper(source_wallet.currency_code) = upper(destination_wallet.currency_code)
            and new.destination_amount_minor is distinct from new.amount_minor
       )
       or (
            upper(source_wallet.currency_code) <> upper(destination_wallet.currency_code)
            and (
                new.destination_amount_minor is null
                or coalesce(new.exchange_rate_decimal_string, '') = ''
                or new.exchange_rate_decimal_string::numeric <= 0
                or round(
                    new.amount_minor::numeric * new.exchange_rate_decimal_string::numeric
                )::bigint <> new.destination_amount_minor
            )
       ) then
        raise exception 'Invalid outbound Investment Wallet transfer';
    end if;

    available_source_balance := source_wallet.current_balance_minor;
    if tg_op = 'UPDATE'
       and old.deleted_at is null
       and old.settlement_role_raw_value = 'investmentTransfer'
       and old.source_wallet_id = source_wallet.id then
        available_source_balance := available_source_balance + old.amount_minor;
    end if;
    if available_source_balance <= 0 or new.amount_minor > available_source_balance then
        raise exception 'Investment Wallet transfer exceeds its positive balance';
    end if;
    return new;
end;
$$;

drop trigger if exists ledger_transactions_enforce_investment_transfer on public.ledger_transactions;
create trigger ledger_transactions_enforce_investment_transfer
before insert or update on public.ledger_transactions
for each row execute function public.enforce_investment_transfer_invariants();

revoke execute on function public.enforce_investment_transfer_invariants() from public, anon, authenticated;

drop policy if exists investment_ledger_insert_gate on public.ledger_transactions;
create policy investment_ledger_insert_gate
on public.ledger_transactions as restrictive for insert to authenticated
with check (
    (
        coalesce(settlement_role_raw_value, '') not like 'investment%'
        and not exists (
            select 1 from public.ledger_wallets w
            where w.id in (source_wallet_id, destination_wallet_id)
              and w.system_purpose_raw_value = 'investmentProfit'
        )
    )
    or (
        settlement_role_raw_value = 'investmentTransfer'
        and public.has_investment_permission(user_id, 'create')
        and source_wallet_id = public.investment_system_wallet_id(user_id)
        and destination_wallet_id is not null
        and destination_wallet_id <> source_wallet_id
        and category_id is null
        and coalesce(reporting_expense_minor, 0) = 0
        and coalesce(reporting_income_minor, 0) = 0
        and public.can_operate_wallet(source_wallet_id)
        and public.can_operate_wallet(destination_wallet_id)
        and exists (
            select 1 from public.ledger_wallets destination
            where destination.id = destination_wallet_id
              and destination.user_id = user_id
              and destination.system_purpose_raw_value is null
              and destination.kind_raw_value <> 'creditCard'
              and destination.deleted_at is null
              and destination.is_archived = false
        )
        and amount_minor > 0
        and amount_minor <= (
            select current_balance_minor from public.ledger_wallets where id = source_wallet_id
        )
    )
);

drop policy if exists investment_ledger_update_gate on public.ledger_transactions;
create policy investment_ledger_update_gate
on public.ledger_transactions as restrictive for update to authenticated
using (
    coalesce(settlement_role_raw_value, '') not like 'investment%'
    or (
        settlement_role_raw_value = 'investmentTransfer'
        and public.has_investment_permission(user_id, 'edit')
    )
)
with check (
    (
        coalesce(settlement_role_raw_value, '') not like 'investment%'
        and not exists (
            select 1 from public.ledger_wallets wallet
            where wallet.id in (source_wallet_id, destination_wallet_id)
              and wallet.system_purpose_raw_value = 'investmentProfit'
        )
    )
    or (
        settlement_role_raw_value = 'investmentTransfer'
        and public.has_investment_permission(user_id, 'edit')
        and source_wallet_id = public.investment_system_wallet_id(user_id)
        and destination_wallet_id is not null
        and destination_wallet_id <> source_wallet_id
        and category_id is null
        and coalesce(reporting_expense_minor, 0) = 0
        and coalesce(reporting_income_minor, 0) = 0
        and amount_minor > 0
        and public.can_operate_wallet(destination_wallet_id)
        and exists (
            select 1 from public.ledger_wallets destination
            where destination.id = destination_wallet_id
              and destination.user_id = user_id
              and destination.system_purpose_raw_value is null
              and destination.kind_raw_value <> 'creditCard'
              and destination.deleted_at is null
              and destination.is_archived = false
        )
    )
);

drop policy if exists investment_ledger_delete_gate on public.ledger_transactions;
create policy investment_ledger_delete_gate
on public.ledger_transactions as restrictive for delete to authenticated
using (
    coalesce(settlement_role_raw_value, '') not like 'investment%'
    or (
        settlement_role_raw_value = 'investmentTransfer'
        and public.has_investment_permission(user_id, 'edit')
    )
);

create or replace function public.sync_investment_transfer_postings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    source_wallet public.ledger_wallets%rowtype;
    destination_wallet public.ledger_wallets%rowtype;
    accounting_minor bigint;
begin
    if tg_op = 'UPDATE' and old.settlement_role_raw_value = 'investmentTransfer'
       and (new.settlement_role_raw_value is distinct from 'investmentTransfer' or new.deleted_at is not null) then
        update public.investment_wallet_postings
        set deleted_at = coalesce(new.deleted_at, new.updated_at), updated_at = new.updated_at,
            sync_version = sync_version + 1,
            last_modified_by_device_id = new.last_modified_by_device_id
        where ledger_transaction_id = old.id and deleted_at is null;
        return null;
    end if;
    if new.settlement_role_raw_value is distinct from 'investmentTransfer' or new.deleted_at is not null then return null; end if;

    select * into source_wallet from public.ledger_wallets where id = new.source_wallet_id;
    select * into destination_wallet from public.ledger_wallets where id = new.destination_wallet_id;
    if source_wallet.system_purpose_raw_value is distinct from 'investmentProfit'
       or destination_wallet.system_purpose_raw_value is not null then
        raise exception 'Investment Wallet transfers are outbound only';
    end if;
    accounting_minor := coalesce(new.reporting_amount_minor, new.amount_minor);

    insert into public.investment_wallet_postings (
        id, user_id, event_id, wallet_id, ledger_transaction_id, role_raw_value,
        amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
        occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id
    ) values (
        public.investment_ledger_id(new.id, 'transfer-source-posting'), new.user_id, new.id,
        source_wallet.id, new.id, 'transferOut', -new.amount_minor, source_wallet.currency_code,
        -accounting_minor, source_wallet.currency_code, new.occurred_at, new.created_at,
        new.updated_at, null, 1, new.last_modified_by_device_id
    ) on conflict (id) do update set
        amount_minor = excluded.amount_minor, accounting_amount_minor = excluded.accounting_amount_minor,
        occurred_at = excluded.occurred_at, updated_at = excluded.updated_at, deleted_at = null,
        last_modified_by_device_id = excluded.last_modified_by_device_id,
        sync_version = public.investment_wallet_postings.sync_version + 1;

    insert into public.investment_wallet_postings (
        id, user_id, event_id, wallet_id, ledger_transaction_id, role_raw_value,
        amount_minor, currency_code, accounting_amount_minor, accounting_currency_code,
        occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id
    ) values (
        public.investment_ledger_id(new.id, 'transfer-destination-posting'), new.user_id, new.id,
        destination_wallet.id, new.id, 'transferIn', coalesce(new.destination_amount_minor, new.amount_minor),
        destination_wallet.currency_code, accounting_minor, source_wallet.currency_code,
        new.occurred_at, new.created_at, new.updated_at, null, 1, new.last_modified_by_device_id
    ) on conflict (id) do update set
        amount_minor = excluded.amount_minor, currency_code = excluded.currency_code,
        accounting_amount_minor = excluded.accounting_amount_minor,
        accounting_currency_code = excluded.accounting_currency_code,
        occurred_at = excluded.occurred_at, updated_at = excluded.updated_at, deleted_at = null,
        last_modified_by_device_id = excluded.last_modified_by_device_id,
        sync_version = public.investment_wallet_postings.sync_version + 1;
    return null;
end;
$$;

drop trigger if exists ledger_transactions_sync_investment_transfer_postings on public.ledger_transactions;
create trigger ledger_transactions_sync_investment_transfer_postings
after insert or update on public.ledger_transactions
for each row execute function public.sync_investment_transfer_postings();

revoke execute on function public.sync_investment_transfer_postings() from public, anon, authenticated;

do $$
declare
    table_name text;
begin
    if exists (
        select 1 from pg_publication
        where pubname = 'supabase_realtime' and puballtables = false
    ) then
        foreach table_name in array array[
            'investment_channels',
            'investment_assets',
            'investment_trades',
            'investment_valuations',
            'investment_wallet_postings'
        ] loop
            if not exists (
                select 1 from pg_publication_tables
                where pubname = 'supabase_realtime'
                  and schemaname = 'public'
                  and tablename = table_name
            ) then
                execute format(
                    'alter publication supabase_realtime add table public.%I',
                    table_name
                );
            end if;
        end loop;
    end if;
end;
$$;

notify pgrst, 'reload schema';
