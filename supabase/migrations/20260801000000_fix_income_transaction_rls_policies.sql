-- Fix RLS 403 Forbidden errors when creating or updating Income transactions
-- (where source_wallet_id is NULL and destination_wallet_id is NOT NULL), and
-- ensure can_manage_transaction and has_due_occurrence_edit_permission properly
-- support family member sync and wallet operation permissions.

-- 1. Update has_due_occurrence_edit_permission to allow family members with view/operation access to sync due occurrence records
create or replace function public.has_due_occurrence_edit_permission(
    target_user_id uuid,
    source_kind text,
    source_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        target_user_id = (select auth.uid())
        or public.has_family_finance_view_access(target_user_id, false)
        or (
            source_kind = 'creditCard'
            and source_id is not null
            and public.can_operate_wallet(source_id)
        )
        or (
            source_kind = 'recurringBill'
            and public.has_family_permission_grant(target_user_id, 'bill', null, 'edit')
        )
        or (
            source_kind = 'installment'
            and public.has_family_permission_grant(target_user_id, 'installment', null, 'edit')
        )
        or public.has_family_permission_grant(target_user_id, 'due', null, 'edit');
$$;

grant execute on function public.has_due_occurrence_edit_permission(uuid, text, uuid) to authenticated;

-- Ensure due_occurrence_records policies use the updated helper function
drop policy if exists "due_occurrence_records_granular_insert" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_insert"
on public.due_occurrence_records
for insert
to authenticated
with check (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id));

drop policy if exists "due_occurrence_records_granular_update" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_update"
on public.due_occurrence_records
for update
to authenticated
using (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id))
with check (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id));

drop policy if exists "due_occurrence_records_granular_delete" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_delete"
on public.due_occurrence_records
for delete
to authenticated
using (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id));


-- 2. Update can_manage_transaction helper function to handle NULL source or destination wallets safely
create or replace function public.can_manage_transaction(
    created_by_user_id uuid,
    source_wallet_id uuid,
    destination_wallet_id uuid,
    owner_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = owner_user_id
        or (
            auth.uid() = created_by_user_id
            and (
                source_wallet_id is null
                or public.can_operate_wallet(source_wallet_id)
            )
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
            and (
                source_wallet_id is not null
                or destination_wallet_id is not null
            )
        )
        or (
            public.has_family_permission_grant(owner_user_id, 'transaction', null, 'edit')
            and (
                source_wallet_id is null
                or public.can_operate_wallet(source_wallet_id)
            )
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
            and (
                source_wallet_id is not null
                or destination_wallet_id is not null
            )
        );
$$;

grant execute on function public.can_manage_transaction(uuid, uuid, uuid, uuid) to authenticated;

-- 3. Update transactions_access_insert policy to support Income transactions (source_wallet_id IS NULL, destination_wallet_id IS NOT NULL)
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
            destination_wallet_id is not null
            and public.can_operate_wallet(destination_wallet_id)
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
            (
                (source_wallet_id is not null and public.can_operate_wallet(source_wallet_id))
                or (destination_wallet_id is not null and public.can_operate_wallet(destination_wallet_id))
            )
            and (
                source_wallet_id is null
                or public.can_operate_wallet(source_wallet_id)
            )
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
            and user_id = public.wallet_owner_user_id(coalesce(source_wallet_id, destination_wallet_id))
            and public.transaction_category_matches_owner(
                category_id,
                public.wallet_owner_user_id(coalesce(source_wallet_id, destination_wallet_id))
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
        or (
            source_wallet_id is null
            and destination_wallet_id is null
            and user_id = (select auth.uid())
            and public.transaction_category_matches_owner(
                category_id,
                (select auth.uid())
            )
        )
    )
);

-- 4. Update transactions_access_update policy to support Income transactions
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
    or public.can_write_settlement_principal_transaction(
        user_id,
        settlement_group_id,
        primary_kind_raw_value,
        transfer_subtype_raw_value,
        settlement_role_raw_value,
        source_wallet_id,
        destination_wallet_id,
        category_id,
        'edit'
    )
)
with check (
    last_modified_by_user_id = (select auth.uid())
    and (
        (
            (
                (source_wallet_id is not null and public.can_operate_wallet(source_wallet_id))
                or (destination_wallet_id is not null and public.can_operate_wallet(destination_wallet_id))
            )
            and (
                source_wallet_id is null
                or public.can_operate_wallet(source_wallet_id)
            )
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
            and user_id = public.wallet_owner_user_id(coalesce(source_wallet_id, destination_wallet_id))
            and public.transaction_category_matches_owner(
                category_id,
                public.wallet_owner_user_id(coalesce(source_wallet_id, destination_wallet_id))
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
            'edit'
        )
        or (
            source_wallet_id is null
            and destination_wallet_id is null
            and user_id = (select auth.uid())
            and public.transaction_category_matches_owner(
                category_id,
                (select auth.uid())
            )
        )
    )
);

notify pgrst, 'reload schema';
