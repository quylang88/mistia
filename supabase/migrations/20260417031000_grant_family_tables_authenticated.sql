-- Fix family screen requests failing with permission denied on family tables.
-- RLS policies require matching table-level grants for PostgREST access.

grant usage on schema public to authenticated;

grant select, insert, update
on table public.families
to authenticated;

grant select, insert, update
on table public.family_memberships
to authenticated;

grant select, insert, update
on table public.family_invites
to authenticated;

grant select, insert, update
on table public.family_wallet_access_grants
to authenticated;
