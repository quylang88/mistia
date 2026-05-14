-- Wallet-use permission is enough to create a transaction on that wallet.
-- Direct wallet usage should not stay local-only because the insert policy blocks
-- the cloud push.

drop policy if exists "transactions_access_insert" on public.ledger_transactions;
create policy "transactions_access_insert"
on public.ledger_transactions
for insert
to authenticated
with check (
    created_by_user_id = auth.uid()
    and last_modified_by_user_id = auth.uid()
    and source_wallet_id is not null
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
);
