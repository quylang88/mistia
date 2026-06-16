-- Shared-expense principal rows are settlement state, not wallet movement.
-- They intentionally have no source/destination wallet, so the normal wallet
-- operation transaction policy must not be the only INSERT/UPDATE path.

create or replace function public.can_write_settlement_principal_transaction(
    owner_user_id uuid,
    target_settlement_group_id uuid,
    target_primary_kind text,
    target_transfer_subtype text,
    target_settlement_role text,
    target_source_wallet_id uuid,
    target_destination_wallet_id uuid,
    target_category_id uuid,
    required_event_scope text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        target_source_wallet_id is null
        and target_destination_wallet_id is null
        and target_category_id is null
        and target_settlement_group_id is not null
        and target_primary_kind = 'transfer'
        and target_transfer_subtype = 'debt'
        and target_settlement_role in ('sharedExpenseReceivable', 'sharedExpensePayable')
        and exists (
            select 1
            from public.settlement_groups sg
            where sg.id = target_settlement_group_id
              and sg.user_id = owner_user_id
              and sg.deleted_at is null
        )
        and (
            public.has_family_permission_grant(owner_user_id, 'event', null, required_event_scope)
            or (
                required_event_scope = 'create'
                and public.has_family_permission_grant(owner_user_id, 'event', null, 'edit')
            )
        );
$$;

grant execute on function public.can_write_settlement_principal_transaction(
    uuid,
    uuid,
    text,
    text,
    text,
    uuid,
    uuid,
    uuid,
    text
) to authenticated;

drop policy if exists "transactions_access_insert" on public.ledger_transactions;
create policy "transactions_access_insert"
on public.ledger_transactions
for insert
to authenticated
with check (
    created_by_user_id = (select auth.uid())
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
            source_wallet_id is not null
            and public.can_manage_transaction(
                created_by_user_id,
                source_wallet_id,
                destination_wallet_id,
                user_id
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
            'edit'
        )
    )
);

drop policy if exists "transactions_access_delete" on public.ledger_transactions;
create policy "transactions_access_delete"
on public.ledger_transactions
for delete
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
);

notify pgrst, 'reload schema';
