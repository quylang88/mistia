-- Repair family_memberships RLS for the create-family flow.
--
-- Creating a family is a two-step client flow:
-- 1. insert public.families with owner_user_id = auth.uid()
-- 2. insert the creator's owner row into public.family_memberships
--
-- Keep roster visibility separate from finance permissions, but make the
-- creator's own membership visible immediately so PostgREST INSERT RETURNING
-- succeeds.

grant usage on schema public to authenticated;

grant select, insert, update
on table public.family_memberships
to authenticated;

create or replace function public.is_family_owner(family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.families f
        where f.id = $1
          and f.owner_user_id = auth.uid()
    );
$$;

create or replace function public.is_family_member(family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.family_memberships fm
        join public.families f on f.id = fm.family_id
        where fm.family_id = $1
          and fm.user_id = auth.uid()
          and fm.deleted_at is null
          and f.deleted_at is null
    );
$$;

drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "family_memberships_self_select" on public.family_memberships;
drop policy if exists "family_memberships_others_select" on public.family_memberships;
drop policy if exists "family_memberships_family_roster_select" on public.family_memberships;
drop policy if exists "family_memberships_self_insert" on public.family_memberships;
drop policy if exists "family_memberships_creator_self_insert" on public.family_memberships;
drop policy if exists "family_memberships_owner_insert" on public.family_memberships;
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
drop policy if exists "family_memberships_update_policy" on public.family_memberships;
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;
drop policy if exists "family_memberships_management_delete" on public.family_memberships;
drop policy if exists "family_memberships_delete_policy" on public.family_memberships;

create policy "family_memberships_self_select"
on public.family_memberships
for select
to authenticated
using (
    user_id = auth.uid()
    and deleted_at is null
);

create policy "family_memberships_family_roster_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and public.is_family_member(family_id)
);

create policy "family_memberships_creator_self_insert"
on public.family_memberships
for insert
to authenticated
with check (
    user_id = auth.uid()
    and public.is_family_owner(family_id)
);

create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (
    public.is_family_owner(family_id)
);

create policy "family_memberships_update_policy"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and (
        user_id = auth.uid()
        or public.is_family_owner(family_id)
    )
)
with check (
    user_id = auth.uid()
    or public.is_family_owner(family_id)
);

create policy "family_memberships_delete_policy"
on public.family_memberships
for delete
to authenticated
using (
    user_id = auth.uid()
    or public.is_family_owner(family_id)
);
