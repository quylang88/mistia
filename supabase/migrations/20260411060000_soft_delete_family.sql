-- Add deleted_at columns for soft delete
alter table public.families add column if not exists deleted_at timestamptz;
alter table public.family_memberships add column if not exists deleted_at timestamptz;
alter table public.family_invites add column if not exists deleted_at timestamptz;

-- Update unique index to allow re-joining/re-creating after soft delete
drop index if exists public.family_memberships_family_user_unique;
create unique index family_memberships_family_user_unique
    on public.family_memberships(family_id, user_id)
    where deleted_at is null;

-- Update RLS policies to exclude soft-deleted records

-- families
drop policy if exists "families_owner_all" on public.families;
create policy "families_owner_all"
on public.families
for all
to authenticated
using (auth.uid() = owner_user_id and deleted_at is null)
with check (auth.uid() = owner_user_id and deleted_at is null);

drop policy if exists "families_member_select" on public.families;
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.family_memberships fm
        where fm.family_id = families.id
          and fm.user_id = auth.uid()
          and fm.deleted_at is null
    )
);

-- family_memberships
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.family_memberships my_fm
        where my_fm.family_id = family_memberships.family_id
          and my_fm.user_id = auth.uid()
          and my_fm.deleted_at is null
    )
);

drop policy if exists "family_memberships_owner_update" on public.family_memberships;
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
)
with check (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
);

-- family_invites
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
)
with check (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
);

drop policy if exists "family_invites_read_by_code" on public.family_invites;
create policy "family_invites_read_by_code"
on public.family_invites
for select
to authenticated
using (deleted_at is null);
