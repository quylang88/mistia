-- ============================================================
-- Fix: Family Membership RLS policies (REVISION 2)
--
-- This migration adopts a more robust approach to RLS:
-- 1. Direct "self" access for SELECT/INSERT/DELETE based on auth.uid() = user_id.
-- 2. Membership-based "others" access for SELECT via helper.
-- 3. Ownership-based access for UPDATE/DELETE via helper.
-- ============================================================

-- A. Cleanup existing policies to avoid conflicts
drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "family_memberships_owner_insert" on public.family_memberships;
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;

-- B. Re-ensure helper functions are current and robust
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

create or replace function public.is_family_owner(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.families
        where id = p_family_id
          and owner_user_id = auth.uid()
    );
$$;

-- C. Define new policies

-- 1. SELECT: Users can always see their own membership
create policy "family_memberships_self_select"
on public.family_memberships
for select
to authenticated
using (user_id = auth.uid());

-- 2. SELECT: Members can view all memberships in their family
create policy "family_memberships_others_select"
on public.family_memberships
for select
to authenticated
using (public.is_family_member(family_id));

-- 3. INSERT: Users can always insert their own membership (initial creating or joining)
create policy "family_memberships_self_insert"
on public.family_memberships
for insert
to authenticated
with check (user_id = auth.uid());

-- 4. INSERT: Family owners can manually add other members
create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (public.is_family_owner(family_id));

-- 5. UPDATE: Family owners can change roles/permissions
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (public.is_family_owner(family_id))
with check (public.is_family_owner(family_id));

-- 6. DELETE: Users can remove themselves OR owners can remove others
create policy "family_memberships_management_delete"
on public.family_memberships
for delete
to authenticated
using (
    user_id = auth.uid()
    or public.is_family_owner(family_id)
);
