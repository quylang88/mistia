-- Restore roster visibility for all active family members.
-- This keeps data-access permissions separate from roster visibility:
-- members can see who is in the family, but finance access still follows
-- the existing wallet/transaction policies.

create or replace function public.is_family_member(family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.family_memberships
    where public.family_memberships.family_id = $1
      and public.family_memberships.user_id = auth.uid()
      and public.family_memberships.deleted_at is null
  );
$$;

create or replace function public.my_active_family_member_user_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct fm.user_id
  from public.family_memberships fm
  where fm.deleted_at is null
    and fm.family_id in (
      select family_id
      from public.family_memberships
      where user_id = auth.uid()
        and deleted_at is null
    );
$$;

drop policy if exists "family_memberships_self_select" on public.family_memberships;
drop policy if exists "family_memberships_others_select" on public.family_memberships;
drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "family_memberships_family_roster_select" on public.family_memberships;

create policy "family_memberships_family_roster_select"
on public.family_memberships
for select
to authenticated
using (
  deleted_at is null
  and public.is_family_member(family_id)
);

drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_family_members"
on public.user_profiles
for select
to authenticated
using (
  auth.uid() = user_id
  or user_id in (select public.my_active_family_member_user_ids())
);
