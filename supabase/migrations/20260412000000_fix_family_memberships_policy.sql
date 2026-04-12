-- Fix infinite loop in family_memberships policy
-- The previous policy caused infinite loop by referencing family_memberships table within its own policy

-- family_memberships - member select
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and (
        user_id = auth.uid()
        or exists (
            select 1 from public.families f
            where f.id = family_memberships.family_id
              and f.owner_user_id = auth.uid()
              and f.deleted_at is null
        )
    )
);
