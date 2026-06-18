-- Relax created_by_user_id check in transactions_access_insert to allow inserts
-- of transactions where the creator ID is mapped to the owner or organizer,
-- provided that the inserting authenticated user has operate access to the wallet
-- or participant access to the settlement group.

drop policy if exists "transactions_access_insert" on public.ledger_transactions;
create policy "transactions_access_insert"
on public.ledger_transactions
for insert
to authenticated
with check (
    (
        created_by_user_id = (select auth.uid())
        or (select auth.uid()) = user_id
        or (
            source_wallet_id is not null
            and public.can_operate_wallet(source_wallet_id)
        )
        or (
            settlement_group_id is not null
            and exists (
                select 1
                from public.settlement_participants sp
                where sp.group_id = settlement_group_id
                  and sp.member_user_id = (select auth.uid())
                  and sp.deleted_at is null
            )
        )
    )
    and last_modified_by_user_id = (select auth.uid())
    and (
        (
            source_wallet_id is not null
            and public.can_operate_wallet(source_wallet_id)
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
            and user_id = public.wallet_owner_user_id(source_wallet_id)
            and public.transaction_category_matches_owner(
                category_id,
                public.wallet_owner_user_id(source_wallet_id)
            )
        )
        or public.can_write_settlement_principal_transaction(
            user_id,
            settlement_group_id,
            primary_kind_raw_value,
            transfer_subtype_raw_value,
            settlement_role_raw_value,
            source_wallet_id,
            destination_wallet_id,
            category_id,
            'create'
        )
    )
);

notify pgrst, 'reload schema';
