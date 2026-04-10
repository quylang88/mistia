-- ============================================================
-- Fix: Self-referencing RLS on family_memberships causes 500
--
-- Problem: family_memberships_member_select policy queries
-- family_memberships inside its own RLS → infinite recursion.
-- Also affects user_profiles_select_family_members and all
-- other policies that join family_memberships.
--
-- Solution: Use a SECURITY DEFINER helper function that
-- bypasses RLS when checking family membership.
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
    where user_id = auth.uid();
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
    );
$$;

-- ============================================================
-- Re-create family_memberships policies using the helper
-- ============================================================

-- SELECT: members can view all memberships in their family
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    public.is_family_member(family_id)
);

-- ============================================================
-- Re-create user_profiles SELECT policy using the helper
-- ============================================================

drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_family_members"
on public.user_profiles
for select
to authenticated
using (
    auth.uid() = user_id
    or user_id in (select public.my_family_member_user_ids())
);

-- ============================================================
-- Re-create finance table policies using the helper
-- ============================================================

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
    )
);

-- ============================================================
-- Re-create families member SELECT using the helper
-- ============================================================

drop policy if exists "families_member_select" on public.families;
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    public.is_family_member(id)
);
