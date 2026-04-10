-- ============================================================
-- Fix: Allow invitees to mark invites as accepted
--
-- Problem: Joining user gets "invalid response" because they
-- don't have UPDATE permission on the family_invites table,
-- causing the markInviteAccepted call to return empty rows.
--
-- Solution: Add an UPDATE policy for authenticated users that
-- allows them to accept active invites.
-- ============================================================

drop policy if exists "family_invites_accept_update" on public.family_invites;
create policy "family_invites_accept_update"
on public.family_invites
for update
to authenticated
using (
    accepted_at is null
    and revoked_at is null
    and expires_at >= now()
)
with check (
    accepted_by_user_id = auth.uid()
);
