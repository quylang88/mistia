-- Tighten event ownership permissions so event records do not inherit access
-- from transaction grants or event participant membership.

create or replace function public.can_manage_event(
    owner_user_id uuid,
    group_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        (select auth.uid()) = owner_user_id
        or public.has_family_permission_grant(owner_user_id, 'event', null, 'edit');
$$;

drop policy if exists "settlement_groups_access_update" on public.settlement_groups;
create policy "settlement_groups_access_update"
on public.settlement_groups
for update
to authenticated
using (
    public.can_manage_event(user_id, id)
)
with check (
    public.can_manage_event(user_id, id)
);

drop policy if exists "settlement_groups_access_delete" on public.settlement_groups;
create policy "settlement_groups_access_delete"
on public.settlement_groups
for delete
to authenticated
using (
    public.can_manage_event(user_id, id)
);

drop policy if exists "settlement_participants_access_insert" on public.settlement_participants;
create policy "settlement_participants_access_insert"
on public.settlement_participants
for insert
to authenticated
with check (
    public.has_family_permission_grant(user_id, 'event', null, 'create')
    or public.can_manage_event(user_id, group_id)
);

drop policy if exists "settlement_participants_access_update" on public.settlement_participants;
create policy "settlement_participants_access_update"
on public.settlement_participants
for update
to authenticated
using (
    public.can_manage_event(user_id, group_id)
)
with check (
    public.can_manage_event(user_id, group_id)
);

drop policy if exists "settlement_participants_access_delete" on public.settlement_participants;
create policy "settlement_participants_access_delete"
on public.settlement_participants
for delete
to authenticated
using (
    public.can_manage_event(user_id, group_id)
);

notify pgrst, 'reload schema';
