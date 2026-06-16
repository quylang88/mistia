-- Update can_manage_event to grant edit/manage permissions to group participants
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
        auth.uid() = owner_user_id
        or public.has_family_permission_grant(owner_user_id, 'event', null, 'edit')
        or (
            group_id is not null
            and exists (
                select 1
                from public.settlement_participants sp
                where sp.group_id = group_id
                  and sp.member_user_id = auth.uid()
                  and sp.deleted_at is null
            )
        );
$$;

-- Update can_write_settlement_principal_transaction to check participant status
create or replace function public.can_write_settlement_principal_transaction(
    owner_user_id uuid,
    target_settlement_group_id uuid,
    target_primary_kind text,
    target_transfer_subtype text,
    target_settlement_role text,
    target_source_wallet_id uuid,
    target_destination_wallet_id uuid,
    target_category_id uuid,
    required_event_scope text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        target_source_wallet_id is null
        and target_destination_wallet_id is null
        and target_category_id is null
        and target_settlement_group_id is not null
        and target_primary_kind = 'transfer'
        and target_transfer_subtype = 'debt'
        and target_settlement_role in ('sharedExpenseReceivable', 'sharedExpensePayable')
        and exists (
            select 1
            from public.settlement_groups sg
            where sg.id = target_settlement_group_id
              and sg.deleted_at is null
              and (
                  sg.user_id = owner_user_id
                  or public.has_family_finance_view_access(owner_user_id, false)
              )
        )
        and exists (
            select 1
            from public.settlement_groups sg
            where sg.id = target_settlement_group_id
              and (
                  public.has_family_permission_grant(sg.user_id, 'event', null, required_event_scope)
                  or (
                      required_event_scope = 'create'
                      and public.has_family_permission_grant(sg.user_id, 'event', null, 'edit')
                  )
                  or exists (
                      select 1
                      from public.settlement_participants sp
                      where sp.group_id = target_settlement_group_id
                        and sp.member_user_id = auth.uid()
                        and sp.deleted_at is null
                  )
              )
        );
$$;

-- Update RLS policies on settlement_groups to pass the group ID to can_manage_event
drop policy if exists "settlement_groups_access_update" on public.settlement_groups;
create policy "settlement_groups_access_update"
on public.settlement_groups
for update
to authenticated
using (
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

-- Update RLS policies on settlement_participants to pass the group ID to can_manage_event
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
