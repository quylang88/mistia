-- Fix can_write_settlement_principal_transaction to support shared-expense principal rows
-- for family members who do not own the event.
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
              and sg.deleted_at is null
              and (
                  sg.user_id = owner_user_id
                  or public.has_family_finance_view_access(owner_user_id, false)
              )
        )
        and exists (
            select 1
            from public.settlement_groups sg
            where sg.id = target_settlement_group_id
              and (
                  public.has_family_permission_grant(sg.user_id, 'event', null, required_event_scope)
                  or (
                      required_event_scope = 'create'
                      and public.has_family_permission_grant(sg.user_id, 'event', null, 'edit')
                  )
              )
        );
$$;

-- Add SELECT policy on ledger_transactions to allow users to view transactions linked
-- to a settlement group they have access to.
drop policy if exists "transactions_settlement_access_select" on public.ledger_transactions;
create policy "transactions_settlement_access_select"
on public.ledger_transactions
for select
to authenticated
using (
    settlement_group_id is not null
    and exists (
        select 1
        from public.settlement_groups sg
        where sg.id = settlement_group_id
          and public.has_family_finance_view_access(sg.user_id, false)
    )
);

notify pgrst, 'reload schema';
