-- Fix enforce_investment_linked_wallet to only require investment 'edit' permission
-- when the linked wallet configuration is actually created or modified,
-- rather than on every wallet balance update caused by trade creation.

create or replace function public.enforce_investment_linked_wallet()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    linked public.ledger_wallets%rowtype;
    retained_minor bigint;
begin
    if new.system_purpose_raw_value = 'investmentProfit' then
        if (tg_op = 'INSERT' or new.investment_linked_wallet_id is distinct from old.investment_linked_wallet_id) then
            if not public.has_investment_permission(new.user_id, 'edit') then
                raise exception 'Investment edit permission is required';
            end if;
            if new.investment_linked_wallet_id is not null then
                select * into linked
                from public.ledger_wallets
                where id = new.investment_linked_wallet_id
                for share;
                if linked.id is null
                   or linked.user_id <> new.user_id
                   or linked.currency_code <> new.currency_code
                   or linked.deleted_at is not null
                   or linked.is_archived
                   or linked.kind_raw_value in ('creditCard', 'investment')
                   or linked.system_purpose_raw_value is not null then
                    raise exception 'Invalid linked investment wallet';
                end if;
                if auth.uid() is distinct from new.user_id
                   and not public.has_family_permission_grant(new.user_id, 'wallet', linked.id, 'use') then
                    raise exception 'Wallet use permission is required';
                end if;
            end if;
        end if;
    elsif new.system_purpose_raw_value is null and new.investment_linked_wallet_id is not null then
        raise exception 'Only the system Investment Wallet can have a linked wallet';
    end if;

    if tg_op = 'UPDATE' and old.system_purpose_raw_value is null then
        if exists (
            select 1 from public.ledger_wallets system_wallet
            where system_wallet.investment_linked_wallet_id = old.id
              and system_wallet.deleted_at is null
        ) and (
            new.user_id is distinct from old.user_id
            or new.currency_code is distinct from old.currency_code
            or new.kind_raw_value is distinct from old.kind_raw_value
            or new.is_archived
            or new.deleted_at is not null
        ) then
            raise exception 'Move investment cash and unlink this wallet before changing or archiving it';
        end if;

        select coalesce(sum(accounting_amount_minor), 0) into retained_minor
        from public.investment_wallet_postings
        where wallet_id = old.id and deleted_at is null and cash_bucket_raw_value is not null;
        if retained_minor <> 0 and (
            new.user_id is distinct from old.user_id
            or new.currency_code is distinct from old.currency_code
            or new.kind_raw_value is distinct from old.kind_raw_value
            or new.is_archived
            or new.deleted_at is not null
        ) then
            raise exception 'Move or adjust the investment cash held by this wallet first';
        end if;
    end if;
    return new;
end;
$$;
