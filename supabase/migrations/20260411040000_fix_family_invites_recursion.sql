-- ============================================================
-- Fix: RLS Recursion between families and family_invites
--
-- Problem: families policy queries family_invites, and
-- family_invites policy queries families -> infinite loop.
--
-- Solution: Use SECURITY DEFINER helpers to break the chain.
-- ============================================================

-- 1. Helper: check for active invites without triggering RLS (SECURITY DEFINER)
create or replace function public.has_active_invite(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.family_invites
        where family_id = p_family_id
          and accepted_at is null
          and revoked_at is null
          and expires_at >= now()
    );
$$;

-- 2. Update families policy to use the helper
drop policy if exists "families_invite_select" on public.families;
create policy "families_invite_select"
on public.families
for select
to authenticated
using (public.has_active_invite(id));

-- 3. Update family_invites policy to use is_family_owner helper
-- is_family_owner is already SECURITY DEFINER, so it breaks the chain
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (public.is_family_owner(family_id))
with check (public.is_family_owner(family_id));
