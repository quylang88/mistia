-- Restore the creator-managed path that was accidentally dropped when
-- transaction edit permissions moved to granular grants. A member who created a
-- transaction through an allowed family wallet must be able to reconcile,
-- update, and delete that same row while the wallet grant is still valid.
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
            and public.can_operate_wallet(source_wallet_id)
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
        )
        or (
            public.has_family_permission_grant(owner_user_id, 'transaction', null, 'edit')
            and public.can_operate_wallet(source_wallet_id)
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
        );
$$;

grant execute on function public.can_manage_transaction(uuid, uuid, uuid, uuid) to authenticated;
