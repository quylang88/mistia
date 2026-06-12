-- Reduce RLS policy overhead reported by Supabase performance advisor.
--
-- The dropped owner policies are legacy FOR ALL policies from the baseline
-- migration. Current family/granular policies already include direct owner
-- access through their helper functions, so keeping the old policies only adds
-- duplicate permissive checks and direct per-row auth.uid() calls.

drop policy if exists "wallets owned by current user" on public.ledger_wallets;
drop policy if exists "credit card profiles owned by current user" on public.credit_card_profiles;
drop policy if exists "categories owned by current user" on public.transaction_categories;
drop policy if exists "transactions owned by current user" on public.ledger_transactions;
drop policy if exists "budget plans owned by current user" on public.budget_plans;
drop policy if exists "savings goals owned by current user" on public.savings_goals;
drop policy if exists "recurring bill plans owned by current user" on public.recurring_bill_plans;
drop policy if exists "installment plans owned by current user" on public.installment_plans;
drop policy if exists "due occurrence records owned by current user" on public.due_occurrence_records;

drop policy if exists "categories_family_access_select" on public.transaction_categories;
drop policy if exists "categories_wallet_use_catalog_select" on public.transaction_categories;
create policy "categories_family_access_select"
on public.transaction_categories
for select
to authenticated
using (
    public.has_family_finance_view_access(user_id, false)
    or public.has_family_wallet_operation_access(user_id)
);

drop policy if exists "transactions_access_insert" on public.ledger_transactions;
create policy "transactions_access_insert"
on public.ledger_transactions
for insert
to authenticated
with check (
    created_by_user_id = (select auth.uid())
    and last_modified_by_user_id = (select auth.uid())
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

drop policy if exists "transactions_access_update" on public.ledger_transactions;
create policy "transactions_access_update"
on public.ledger_transactions
for update
to authenticated
using (
    public.can_manage_transaction(
        created_by_user_id,
        source_wallet_id,
        destination_wallet_id,
        user_id
    )
)
with check (
    source_wallet_id is not null
    and public.can_manage_transaction(
        created_by_user_id,
        source_wallet_id,
        destination_wallet_id,
        user_id
    )
    and last_modified_by_user_id = (select auth.uid())
    and user_id = public.wallet_owner_user_id(source_wallet_id)
    and public.transaction_category_matches_owner(
        category_id,
        public.wallet_owner_user_id(source_wallet_id)
    )
);

-- Settlement rows do not have granular edit grants yet. Keep owner writes, but
-- remove the legacy FOR ALL policy so SELECT has only the family-access policy.

drop policy if exists "settlement_groups_owned_all" on public.settlement_groups;
drop policy if exists "settlement_groups_owner_insert" on public.settlement_groups;
drop policy if exists "settlement_groups_owner_update" on public.settlement_groups;
drop policy if exists "settlement_groups_owner_delete" on public.settlement_groups;

create policy "settlement_groups_owner_insert"
on public.settlement_groups
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "settlement_groups_owner_update"
on public.settlement_groups
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "settlement_groups_owner_delete"
on public.settlement_groups
for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "settlement_participants_owned_all" on public.settlement_participants;
drop policy if exists "settlement_participants_owner_insert" on public.settlement_participants;
drop policy if exists "settlement_participants_owner_update" on public.settlement_participants;
drop policy if exists "settlement_participants_owner_delete" on public.settlement_participants;

create policy "settlement_participants_owner_insert"
on public.settlement_participants
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "settlement_participants_owner_update"
on public.settlement_participants
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "settlement_participants_owner_delete"
on public.settlement_participants
for delete
to authenticated
using ((select auth.uid()) = user_id);

-- Cover foreign-key columns surfaced by the advisor on finance tables.

create index if not exists budget_plans_category_id_idx
on public.budget_plans(category_id);

create index if not exists credit_card_profiles_payment_source_wallet_id_idx
on public.credit_card_profiles(payment_source_wallet_id);

create index if not exists installment_plans_payment_wallet_id_idx
on public.installment_plans(payment_wallet_id);

create index if not exists ledger_transactions_category_id_idx
on public.ledger_transactions(category_id);

create index if not exists ledger_transactions_last_modified_by_user_id_idx
on public.ledger_transactions(last_modified_by_user_id);

create index if not exists recurring_bill_plans_category_id_idx
on public.recurring_bill_plans(category_id);

create index if not exists recurring_bill_plans_payment_wallet_id_idx
on public.recurring_bill_plans(payment_wallet_id);

create index if not exists savings_goals_linked_wallet_id_idx
on public.savings_goals(linked_wallet_id);

create index if not exists settlement_groups_organizer_user_id_idx
on public.settlement_groups(organizer_user_id);

create index if not exists settlement_participants_member_user_id_idx
on public.settlement_participants(member_user_id);

create index if not exists transaction_categories_parent_category_id_idx
on public.transaction_categories(parent_category_id);

notify pgrst, 'reload schema';
