-- Wallet-use transaction creation now relies on the wallet owner's existing
-- category catalog. Members who can use a wallet only need catalog SELECT, not
-- category INSERT/UPDATE bootstrap privileges.

drop policy if exists "categories_wallet_use_system_select" on public.transaction_categories;
drop policy if exists "categories_wallet_use_system_insert" on public.transaction_categories;
drop policy if exists "categories_wallet_use_system_update" on public.transaction_categories;

notify pgrst, 'reload schema';
