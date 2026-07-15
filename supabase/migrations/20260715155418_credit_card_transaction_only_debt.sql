-- Credit-card debt starts from posted transactions. The shared opening balance
-- column remains available to non-card wallets, but is ignored for cards.

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
      case
        when p_wallet_kind = 'creditCard' then 0
        else p_opening_balance_minor
      end
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
    else
      (select balance_minor from raw_balance)
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
