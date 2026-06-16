-- Align family roles and permission semantics with the product model:
-- owner/member/kid, view access separate from wallet operation/edit access.

alter table public.family_memberships
    alter column role set default 'member';

alter table public.family_invites
    alter column default_role set default 'member';

update public.family_memberships
set role = 'member'
where role in ('viewer', 'editor');

update public.family_invites
set default_role = 'member'
where default_role in ('viewer', 'editor');

update public.family_memberships
set can_view_family_dashboard = true,
    can_view_others = true,
    can_edit_others = false,
    can_view_wallets = true,
    can_view_debts = true,
    can_view_kids = true,
    can_edit_kids = false
where role in ('owner', 'member')
  and deleted_at is null;

create or replace function public.has_family_finance_view_access(
    target_user_id uuid,
    require_wallet_scope boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = target_user_id
        or exists (
            select 1
            from public.family_memberships viewer_membership
            join public.family_memberships target_membership
              on target_membership.family_id = viewer_membership.family_id
            join public.families f
              on f.id = viewer_membership.family_id
            where viewer_membership.user_id = auth.uid()
              and target_membership.user_id = target_user_id
              and viewer_membership.deleted_at is null
              and target_membership.deleted_at is null
              and f.deleted_at is null
              and viewer_membership.can_view_others = true
              and (
                  require_wallet_scope = false
                  or viewer_membership.can_view_wallets = true
              )
              and (
                  target_membership.role <> 'kid'
                  or viewer_membership.can_view_kids = true
              )
        );
$$;

create or replace function public.has_family_wallet_access(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.has_family_finance_view_access(target_user_id, true);
$$;

create or replace function public.has_family_wallet_operation_access(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = target_user_id
        or exists (
            select 1
            from public.family_wallet_access_grants g
            join public.families f
              on f.id = g.family_id
            join public.family_memberships grantee_membership
              on grantee_membership.family_id = g.family_id
             and grantee_membership.user_id = g.grantee_user_id
            join public.family_memberships target_membership
              on target_membership.family_id = g.family_id
             and target_membership.user_id = g.target_user_id
            where g.grantee_user_id = auth.uid()
              and g.target_user_id = target_user_id
              and g.revoked_at is null
              and f.deleted_at is null
              and grantee_membership.deleted_at is null
              and target_membership.deleted_at is null
        );
$$;

create or replace function public.can_operate_wallet(target_wallet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.ledger_wallets w
        where w.id = target_wallet_id
          and public.has_family_wallet_operation_access(w.user_id)
    );
$$;

create or replace function public.can_read_transaction(
    owner_user_id uuid,
    created_by_user_id uuid,
    source_wallet_id uuid,
    destination_wallet_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        public.has_family_finance_view_access(owner_user_id, false)
        or auth.uid() = created_by_user_id
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = source_wallet_id
              and w.user_id = auth.uid()
        )
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = destination_wallet_id
              and w.user_id = auth.uid()
        );
$$;

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
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = source_wallet_id
              and w.user_id = auth.uid()
        )
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = destination_wallet_id
              and w.user_id = auth.uid()
        );
$$;
