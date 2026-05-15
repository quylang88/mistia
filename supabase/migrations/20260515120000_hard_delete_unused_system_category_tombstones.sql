-- Permanently remove system-category tombstones that are no longer referenced.
--
-- The previous cleanup intentionally soft-deleted unused system categories so
-- other devices could observe the delete. Those tombstones can now block a
-- later legitimate upload of the same system category. This migration only
-- removes rows whose deletion will not null out finance references or leave
-- family permission metadata pointing at a missing category.

create temporary table mistia_unused_system_category_tombstones (
    id uuid primary key
) on commit drop;

insert into mistia_unused_system_category_tombstones (id)
select c.id
from public.transaction_categories c
where c.is_system = true
  and c.system_key is not null
  and c.deleted_at is not null
  and not exists (
      select 1
      from public.transaction_categories child
      where child.parent_category_id = c.id
  )
  and not exists (
      select 1
      from public.ledger_transactions t
      where t.category_id = c.id
  )
  and not exists (
      select 1
      from public.budget_plans b
      where b.category_id = c.id
  )
  and not exists (
      select 1
      from public.recurring_bill_plans r
      where r.category_id = c.id
  )
  and not exists (
      select 1
      from public.family_permission_requests r
      where r.resource_type = 'category'
        and r.resource_id = c.id
  )
  and not exists (
      select 1
      from public.family_permission_grants g
      where g.resource_type = 'category'
        and g.resource_id = c.id
  )
  and not exists (
      select 1
      from public.family_notifications n
      where n.resource_type = 'category'
        and n.resource_id = c.id
  );

delete from public.transaction_categories c
using mistia_unused_system_category_tombstones target
where target.id = c.id;
