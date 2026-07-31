-- Fix RLS 403 Forbidden on due_occurrence_records for family members

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
    select
        target_user_id = (select auth.uid())
        or public.has_family_finance_view_access(target_user_id, false)
        or (
            source_kind = 'creditCard'
            and source_id is not null
            and public.can_operate_wallet(source_id)
        )
        or (
            source_kind = 'recurringBill'
            and public.has_family_permission_grant(target_user_id, 'bill', null, 'edit')
        )
        or (
            source_kind = 'installment'
            and public.has_family_permission_grant(target_user_id, 'installment', null, 'edit')
        )
        or public.has_family_permission_grant(target_user_id, 'due', null, 'edit');
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

notify pgrst, 'reload schema';
