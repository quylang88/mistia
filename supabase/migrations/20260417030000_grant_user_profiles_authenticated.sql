-- Fix Google/email sign-in failing on user_profiles with:
-- permission denied for table user_profiles
--
-- RLS policies alone are not enough; PostgREST also requires table-level grants.
-- Grant the minimum privileges needed by the app's profile fetch/upsert flow.

grant usage on schema public to authenticated;

grant select, insert, update
on table public.user_profiles
to authenticated;
