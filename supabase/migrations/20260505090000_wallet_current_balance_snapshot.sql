-- Keep a denormalized wallet balance on the cloud row for inspection and
-- family/cloud consumers that read ledger_wallets directly. The app still
-- treats transactions as the source of truth for local balance math.

alter table public.ledger_wallets
  add column if not exists current_balance_minor bigint not null default 0;

create or replace function public.mistia_wallet_balance_delta(
  p_wallet_kind text,
  p_primary_kind text,
  p_transfer_subtype text,
  p_debt_intent text,
  p_amount_minor bigint,
  p_wallet_role text
)
returns bigint
language sql
immutable
as $$
  select case
    when p_primary_kind = 'expense' and p_wallet_role = 'source' then
      case when p_wallet_kind = 'creditCard' then p_amount_minor else -p_amount_minor end
    when p_primary_kind = 'income' and p_wallet_role = 'source' then
      case when p_wallet_kind = 'creditCard' then -p_amount_minor else p_amount_minor end
    when p_primary_kind = 'transfer'
      and p_transfer_subtype = 'internalTransfer'
      and p_wallet_role = 'source' then
      case when p_wallet_kind = 'creditCard' then p_amount_minor else -p_amount_minor end
    when p_primary_kind = 'transfer'
      and p_transfer_subtype = 'internalTransfer'
      and p_wallet_role = 'destination' then
      case when p_wallet_kind = 'creditCard' then -p_amount_minor else p_amount_minor end
    when p_primary_kind = 'transfer'
      and p_transfer_subtype = 'debt'
      and p_wallet_role = 'source'
      and p_debt_intent in ('lend', 'repay') then
      case when p_wallet_kind = 'creditCard' then p_amount_minor else -p_amount_minor end
    when p_primary_kind = 'transfer'
      and p_transfer_subtype = 'debt'
      and p_wallet_role = 'source'
      and p_debt_intent in ('collect', 'borrow') then
      case when p_wallet_kind = 'creditCard' then -p_amount_minor else p_amount_minor end
    else 0
  end;
$$;

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
  select p_opening_balance_minor + coalesce(
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
              tx.amount_minor,
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
        and (
          tx.source_wallet_id = p_wallet_id
          or tx.destination_wallet_id = p_wallet_id
        )
    ),
    0
  );
$$;

create or replace function public.mistia_recalculate_wallet_current_balance(
  p_wallet_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with calculated as (
    select
      wallet.id,
      public.mistia_calculate_wallet_current_balance(
        wallet.id,
        wallet.user_id,
        wallet.kind_raw_value,
        wallet.opening_balance_minor
      ) as current_balance_minor
    from public.ledger_wallets wallet
    where wallet.id = p_wallet_id
  )
  update public.ledger_wallets wallet
  set current_balance_minor = calculated.current_balance_minor
  from calculated
  where wallet.id = calculated.id
    and wallet.current_balance_minor is distinct from calculated.current_balance_minor;
end;
$$;

create or replace function public.mistia_set_wallet_current_balance()
returns trigger
language plpgsql
as $$
begin
  new.current_balance_minor := public.mistia_calculate_wallet_current_balance(
    new.id,
    new.user_id,
    new.kind_raw_value,
    new.opening_balance_minor
  );
  return new;
end;
$$;

create or replace function public.mistia_refresh_wallet_balances_from_transaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    if old.source_wallet_id is not null then
      perform public.mistia_recalculate_wallet_current_balance(old.source_wallet_id);
    end if;

    if old.destination_wallet_id is not null
      and old.destination_wallet_id is distinct from old.source_wallet_id then
      perform public.mistia_recalculate_wallet_current_balance(old.destination_wallet_id);
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if new.source_wallet_id is not null then
      perform public.mistia_recalculate_wallet_current_balance(new.source_wallet_id);
    end if;

    if new.destination_wallet_id is not null
      and new.destination_wallet_id is distinct from new.source_wallet_id then
      perform public.mistia_recalculate_wallet_current_balance(new.destination_wallet_id);
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists ledger_wallets_set_current_balance on public.ledger_wallets;
create trigger ledger_wallets_set_current_balance
before insert or update of opening_balance_minor, kind_raw_value on public.ledger_wallets
for each row
execute function public.mistia_set_wallet_current_balance();

drop trigger if exists ledger_transactions_refresh_wallet_balances on public.ledger_transactions;
create trigger ledger_transactions_refresh_wallet_balances
after insert or update or delete on public.ledger_transactions
for each row
execute function public.mistia_refresh_wallet_balances_from_transaction();

revoke execute on function public.mistia_recalculate_wallet_current_balance(uuid) from public;

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
