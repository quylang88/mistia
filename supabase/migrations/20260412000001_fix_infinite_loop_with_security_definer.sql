-- Fix infinite loop in family_memberships policy using SECURITY DEFINER function
-- The issue: circular RLS references cause infinite loops
-- Solution: Use helper functions with SECURITY DEFINER to bypass RLS recursion

-- Drop old policies first
drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "families_member_select" on public.families;

-- Drop existing functions if they exist
drop function if exists public.is_family_member(uuid) cascade;
drop function if exists public.is_family_owner(uuid) cascade;

-- Create helper functions with SECURITY DEFINER to bypass RLS
create function public.is_family_member(family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.family_memberships
    where family_memberships.family_id = $1
      and family_memberships.user_id = auth.uid()
      and family_memberships.deleted_at is null
  );
$$;

create function public.is_family_owner(family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.families
    where families.id = $1
      and families.owner_user_id = auth.uid()
      and families.deleted_at is null
  );
$$;

-- New policies using helper functions
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    deleted_at is null
    and (
        auth.uid() = owner_user_id
        or public.is_family_member(id)
    )
);

create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and (
        user_id = auth.uid()
        or public.is_family_owner(family_id)
    )
);
