-- Add deleted_at columns for soft delete
alter table public.families add column if not exists deleted_at timestamptz;
alter table public.family_memberships add column if not exists deleted_at timestamptz;
alter table public.family_invites add column if not exists deleted_at timestamptz;

-- Update unique index to allow re-joining/re-creating after soft delete
drop index if exists public.family_memberships_family_user_unique;
create unique index family_memberships_family_user_unique
    on public.family_memberships(family_id, user_id)
    where deleted_at is null;

-- ============================================================
-- Update Helper Functions to support soft delete
-- ============================================================

-- 1. Helper: check if current user belongs to a given family (bypasses RLS)
create or replace function public.is_family_member(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.family_memberships
        where family_id = p_family_id
          and user_id = auth.uid()
          and deleted_at is null
    );
$$;

-- 2. Helper: get all family_ids the current user belongs to (bypasses RLS)
create or replace function public.my_family_ids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
    select family_id from public.family_memberships
    where user_id = auth.uid()
      and deleted_at is null;
$$;

-- 3. Helper: get all user_ids that share a family with the current user (bypasses RLS)
create or replace function public.my_family_member_user_ids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
    select distinct fm.user_id
    from public.family_memberships fm
    where fm.family_id in (
        select family_id from public.family_memberships
        where user_id = auth.uid()
          and deleted_at is null
    )
    and fm.deleted_at is null;
$$;

-- ============================================================
-- Update RLS policies using helpers to avoid infinite recursion
-- ============================================================

-- families: Owner can do everything
drop policy if exists "families_owner_all" on public.families;
create policy "families_owner_all"
on public.families
for all
to authenticated
using (auth.uid() = owner_user_id and deleted_at is null)
with check (auth.uid() = owner_user_id and deleted_at is null);

-- families: Members can read
drop policy if exists "families_member_select" on public.families;
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    deleted_at is null
    and public.is_family_member(id)
);

-- family_memberships: Members can view all memberships in their family
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and public.is_family_member(family_id)
);

-- family_memberships: Family owner can update memberships
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
)
with check (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
);

-- family_invites
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
)
with check (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
);

drop policy if exists "family_invites_read_by_code" on public.family_invites;
create policy "family_invites_read_by_code"
on public.family_invites
for select
to authenticated
using (deleted_at is null);

-- user_profiles SELECT policy using the helper
drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_family_members"
on public.user_profiles
for select
to authenticated
using (
    auth.uid() = user_id
    or user_id in (select public.my_family_member_user_ids())
);

-- Finance table policies using the helper

-- Wallets
drop policy if exists "wallets_family_member_select" on public.ledger_wallets;
create policy "wallets_family_member_select"
on public.ledger_wallets
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships fm
        where fm.family_id in (select public.my_family_ids())
          and fm.user_id = ledger_wallets.user_id
          and fm.can_view_wallets = true
          and fm.deleted_at is null
    )
);

-- Transactions
drop policy if exists "transactions_family_member_select" on public.ledger_transactions;
create policy "transactions_family_member_select"
on public.ledger_transactions
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships fm
        where fm.family_id in (select public.my_family_ids())
          and fm.user_id = ledger_transactions.user_id
          and fm.can_view_others = true
          and fm.deleted_at is null
    )
);

-- Categories
drop policy if exists "categories_family_member_select" on public.transaction_categories;
create policy "categories_family_member_select"
on public.transaction_categories
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships fm
        where fm.family_id in (select public.my_family_ids())
          and fm.user_id = transaction_categories.user_id
          and fm.can_view_others = true
          and fm.deleted_at is null
    )
);
