-- ============================================================
-- Fix: Family Membership RLS policies
--
-- This migration fixes the "new row violates policy" error
-- by allowing users to insert their own initial membership
-- and by using a non-recursive owner check helper.
-- ============================================================

-- 1. Helper: check if current user is owner of a given family (bypasses RLS)
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

-- 2. family_memberships: INSERT
-- Family owner can add members OR any user can insert their OWN initial membership
drop policy if exists "family_memberships_owner_insert" on public.family_memberships;
create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (
    public.is_family_owner(family_id)
    or user_id = auth.uid()
);

-- 3. family_memberships: UPDATE
-- Family owner can change roles/permissions
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (
    public.is_family_owner(family_id)
)
with check (
    public.is_family_owner(family_id)
);

-- 4. family_memberships: DELETE
-- Family owner can remove members OR any user can remove THEMSELVES
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;
create policy "family_memberships_owner_delete"
on public.family_memberships
for delete
to authenticated
using (
    public.is_family_owner(family_id)
    or user_id = auth.uid()
);
