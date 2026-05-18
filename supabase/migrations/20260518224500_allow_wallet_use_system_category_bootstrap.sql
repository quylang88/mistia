-- Wallet-use transaction inserts can depend on default system categories that
-- have not been bootstrapped into the wallet owner's cloud catalog yet.
-- Allow only predefined system-category rows to be read, seeded, or restored by
-- a family member who can operate at least one wallet for that owner.

drop policy if exists "categories_wallet_use_system_select" on public.transaction_categories;
create policy "categories_wallet_use_system_select"
on public.transaction_categories
for select
to authenticated
using (
    is_system = true
    and system_key is not null
    and public.has_family_wallet_operation_access(user_id)
);

drop policy if exists "categories_wallet_use_system_insert" on public.transaction_categories;
create policy "categories_wallet_use_system_insert"
on public.transaction_categories
for insert
to authenticated
with check (
    is_system = true
    and system_key is not null
    and deleted_at is null
    and public.has_family_wallet_operation_access(user_id)
);

drop policy if exists "categories_wallet_use_system_update" on public.transaction_categories;
create policy "categories_wallet_use_system_update"
on public.transaction_categories
for update
to authenticated
using (
    is_system = true
    and system_key is not null
    and deleted_at is not null
    and public.has_family_wallet_operation_access(user_id)
)
with check (
    is_system = true
    and system_key is not null
    and deleted_at is null
    and public.has_family_wallet_operation_access(user_id)
);

notify pgrst, 'reload schema';
