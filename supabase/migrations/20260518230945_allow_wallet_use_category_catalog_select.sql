-- Wallet-use permission must be enough to read the wallet owner's category
-- catalog. The transaction editor uses that catalog directly, and transaction
-- creation should reuse those existing category IDs.

drop policy if exists "categories_wallet_use_catalog_select" on public.transaction_categories;
create policy "categories_wallet_use_catalog_select"
on public.transaction_categories
for select
to authenticated
using (
    public.has_family_wallet_operation_access(user_id)
);

notify pgrst, 'reload schema';
