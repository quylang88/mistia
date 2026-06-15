-- Family Event Permissions Migration

alter table public.family_permission_grants
    drop constraint if exists family_permission_grants_resource_type_check,
    add constraint family_permission_grants_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'event'));

alter table public.family_permission_requests
    drop constraint if exists family_permission_requests_resource_type_check,
    add constraint family_permission_requests_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'event'));

alter table public.family_notifications
    drop constraint if exists family_notifications_resource_type_check,
    add constraint family_notifications_resource_type_check
        check (resource_type is null or resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'event'));

create or replace function public.family_resource_owner_user_id(
    p_resource_type text,
    p_resource_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    owner_id uuid;
begin
    if p_resource_id is null then
        return null;
    end if;

    case p_resource_type
        when 'wallet' then
            select user_id into owner_id from public.ledger_wallets where id = p_resource_id limit 1;
        when 'category' then
            select user_id into owner_id from public.transaction_categories where id = p_resource_id limit 1;
        when 'budget' then
            select user_id into owner_id from public.budget_plans where id = p_resource_id limit 1;
        when 'goal' then
            select user_id into owner_id from public.savings_goals where id = p_resource_id limit 1;
        when 'card' then
            select user_id into owner_id from public.credit_card_profiles where id = p_resource_id limit 1;
        when 'transaction' then
            select user_id into owner_id from public.ledger_transactions where id = p_resource_id limit 1;
        when 'bill' then
            select user_id into owner_id from public.recurring_bill_plans where id = p_resource_id limit 1;
        when 'due' then
            select user_id into owner_id from public.due_occurrence_records where id = p_resource_id limit 1;
        when 'installment' then
            select user_id into owner_id from public.installment_plans where id = p_resource_id limit 1;
        when 'event' then
            select user_id into owner_id from public.settlement_groups where id = p_resource_id limit 1;
        else
            owner_id := null;
    end case;

    return owner_id;
end;
$$;

create or replace function public.can_manage_event(
    owner_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = owner_user_id
        or public.has_family_permission_grant(owner_user_id, 'event', null, 'edit');
$$;

drop policy if exists "settlement_groups_owner_insert" on public.settlement_groups;
create policy "settlement_groups_access_insert"
on public.settlement_groups
for insert
to authenticated
with check (
    public.has_family_permission_grant(user_id, 'event', null, 'create')
);

drop policy if exists "settlement_groups_owner_update" on public.settlement_groups;
create policy "settlement_groups_access_update"
on public.settlement_groups
for update
to authenticated
using (
    public.can_manage_event(user_id)
);

drop policy if exists "settlement_groups_owner_delete" on public.settlement_groups;
create policy "settlement_groups_access_delete"
on public.settlement_groups
for delete
to authenticated
using (
    public.can_manage_event(user_id)
);

drop policy if exists "settlement_participants_owner_insert" on public.settlement_participants;
create policy "settlement_participants_access_insert"
on public.settlement_participants
for insert
to authenticated
with check (
    public.has_family_permission_grant(user_id, 'event', null, 'create')
    or public.can_manage_event(user_id)
);

drop policy if exists "settlement_participants_owner_update" on public.settlement_participants;
create policy "settlement_participants_access_update"
on public.settlement_participants
for update
to authenticated
using (
    public.can_manage_event(user_id)
);

drop policy if exists "settlement_participants_owner_delete" on public.settlement_participants;
create policy "settlement_participants_access_delete"
on public.settlement_participants
for delete
to authenticated
using (
    public.can_manage_event(user_id)
);
