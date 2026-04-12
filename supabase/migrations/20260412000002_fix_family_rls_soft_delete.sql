-- Fix RLS policies to allow soft delete (setting deleted_at)
-- and allow members to leave families (self-update)

-- 1. Update is_family_owner to ignore deleted_at of the family
-- This allows the owner to soft-delete associated records (memberships, invites)
-- even after the family record itself has been soft-deleted.
create or replace function public.is_family_owner(family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.families
    where families.id = $1
      and families.owner_user_id = auth.uid()
  );
$$;

-- 2. families: Allow owner to update the record (including soft-delete)
-- We remove the 'deleted_at is null' check from WITH CHECK to allow setting it.
drop policy if exists "families_owner_all" on public.families;
create policy "families_owner_all"
on public.families
for all
to authenticated
using (auth.uid() = owner_user_id and deleted_at is null)
with check (auth.uid() = owner_user_id);

-- 3. family_memberships: Allow owner to manage and members to leave
-- Drop old restrictive policies
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;

-- New update policy:
-- - Allows members to update their own membership (e.g., to leave the family)
-- - Allows family owner to update any membership in their family
-- - Removes 'deleted_at is null' from WITH CHECK to allow the actual soft-delete update.
create policy "family_memberships_update_policy"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and (user_id = auth.uid() or public.is_family_owner(family_id))
)
with check (
    user_id = auth.uid() or public.is_family_owner(family_id)
);

-- Also add a delete policy for completeness (though app uses soft-delete)
create policy "family_memberships_delete_policy"
on public.family_memberships
for delete
to authenticated
using (
    user_id = auth.uid() or public.is_family_owner(family_id)
);

-- 4. family_invites: Allow owner to soft-delete invites
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (
    deleted_at is null
    and public.is_family_owner(family_id)
)
with check (
    public.is_family_owner(family_id)
);
