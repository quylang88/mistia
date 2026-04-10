-- ============================================================
-- Fix: Allow viewing families via active invite codes
--
-- Problem: Join process fails with "Family not found" because
-- non-members cannot see the family row they are trying to join.
--
-- Solution: Add a SELECT policy to the families table that grants
-- access if any active, non-expired invite exists for that family.
-- ============================================================

drop policy if exists "families_invite_select" on public.families;
create policy "families_invite_select"
on public.families
for select
to authenticated
using (
    exists (
        select 1 from public.family_invites fi
        where fi.family_id = id
          and fi.accepted_at is null
          and fi.revoked_at is null
          and fi.expires_at >= now()
    )
);
