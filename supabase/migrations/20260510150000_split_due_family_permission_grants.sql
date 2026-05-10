-- Split the previously shared "due" operation grant into bill and installment
-- grants, while preserving existing active due grants for deployed databases.

insert into public.family_permission_grants (
    family_id,
    grantee_user_id,
    owner_user_id,
    resource_type,
    resource_id,
    permission_scope,
    granted_by_user_id,
    created_at,
    updated_at,
    revoked_at
)
select
    g.family_id,
    g.grantee_user_id,
    g.owner_user_id,
    target.resource_type,
    null,
    g.permission_scope,
    g.granted_by_user_id,
    g.created_at,
    timezone('utc'::text, now()),
    null
from public.family_permission_grants g
cross join (values ('bill'), ('installment')) as target(resource_type)
where g.resource_type = 'due'
  and g.resource_id is null
  and g.permission_scope in ('create', 'edit')
  and g.revoked_at is null
on conflict do nothing;

drop policy if exists "recurring_bill_plans_granular_insert" on public.recurring_bill_plans;
create policy "recurring_bill_plans_granular_insert"
on public.recurring_bill_plans
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'bill', null, 'create'));

drop policy if exists "recurring_bill_plans_granular_update" on public.recurring_bill_plans;
create policy "recurring_bill_plans_granular_update"
on public.recurring_bill_plans
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'bill', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'bill', null, 'edit'));

drop policy if exists "recurring_bill_plans_granular_delete" on public.recurring_bill_plans;
create policy "recurring_bill_plans_granular_delete"
on public.recurring_bill_plans
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'bill', null, 'edit'));

drop policy if exists "installment_plans_granular_insert" on public.installment_plans;
create policy "installment_plans_granular_insert"
on public.installment_plans
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'installment', null, 'create'));

drop policy if exists "installment_plans_granular_update" on public.installment_plans;
create policy "installment_plans_granular_update"
on public.installment_plans
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'installment', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'installment', null, 'edit'));

drop policy if exists "installment_plans_granular_delete" on public.installment_plans;
create policy "installment_plans_granular_delete"
on public.installment_plans
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'installment', null, 'edit'));

create or replace function public.has_due_occurrence_edit_permission(
    target_user_id uuid,
    source_kind text,
    source_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select case
        when target_user_id = auth.uid() then true
        when source_kind = 'creditCard' then public.has_family_permission_grant(target_user_id, 'wallet', source_id, 'edit')
        when source_kind = 'recurringBill' then public.has_family_permission_grant(target_user_id, 'bill', null, 'edit')
        when source_kind = 'installment' then public.has_family_permission_grant(target_user_id, 'installment', null, 'edit')
        else public.has_family_permission_grant(target_user_id, 'due', null, 'edit')
    end;
$$;

grant execute on function public.has_due_occurrence_edit_permission(uuid, text, uuid) to authenticated;

drop policy if exists "due_occurrence_records_granular_insert" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_insert"
on public.due_occurrence_records
for insert
to authenticated
with check (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id));

drop policy if exists "due_occurrence_records_granular_update" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_update"
on public.due_occurrence_records
for update
to authenticated
using (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id))
with check (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id));

drop policy if exists "due_occurrence_records_granular_delete" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_delete"
on public.due_occurrence_records
for delete
to authenticated
using (public.has_due_occurrence_edit_permission(user_id, source_kind_raw_value, source_id));
