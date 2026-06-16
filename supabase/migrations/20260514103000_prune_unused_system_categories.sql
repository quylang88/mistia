-- Prune Mistia system-category rows that were uploaded as unused seed data.
--
-- This is intentionally scoped to the two affected users inspected in production.
-- It preserves user-created categories, business-linked categories, and parent
-- categories required by those linked categories.

create temporary table mistia_category_prune_target_users (
    user_id uuid primary key
) on commit drop;

insert into mistia_category_prune_target_users (user_id)
values
    ('89656e23-45f3-4e5a-85ac-d3e079e9b659'::uuid),
    ('c67dd228-5aec-4fa2-8f62-fbbfd36d7c69'::uuid);

create temporary table mistia_business_category_roots (
    id uuid primary key
) on commit drop;

insert into mistia_business_category_roots (id)
select distinct category_id
from public.ledger_transactions
where user_id in (select user_id from mistia_category_prune_target_users)
  and category_id is not null
  and deleted_at is null
on conflict do nothing;

insert into mistia_business_category_roots (id)
select distinct category_id
from public.budget_plans
where user_id in (select user_id from mistia_category_prune_target_users)
  and category_id is not null
  and deleted_at is null
on conflict do nothing;

insert into mistia_business_category_roots (id)
select distinct category_id
from public.recurring_bill_plans
where user_id in (select user_id from mistia_category_prune_target_users)
  and category_id is not null
  and deleted_at is null
on conflict do nothing;

insert into mistia_business_category_roots (id)
select distinct resource_id
from public.family_permission_requests
where resource_type = 'category'
  and (
      requester_user_id in (select user_id from mistia_category_prune_target_users)
      or recipient_user_id in (select user_id from mistia_category_prune_target_users)
  )
on conflict do nothing;

insert into mistia_business_category_roots (id)
select distinct resource_id
from public.family_permission_grants
where resource_type = 'category'
  and resource_id is not null
  and revoked_at is null
  and owner_user_id in (select user_id from mistia_category_prune_target_users)
on conflict do nothing;

insert into mistia_business_category_roots (id)
select distinct resource_id
from public.family_notifications
where resource_type = 'category'
  and resource_id is not null
  and user_id in (select user_id from mistia_category_prune_target_users)
on conflict do nothing;

create temporary table mistia_keep_categories (
    id uuid primary key
) on commit drop;

with recursive category_tree as (
    select c.id, c.parent_category_id
    from public.transaction_categories c
    join mistia_business_category_roots roots on roots.id = c.id
    join mistia_category_prune_target_users target_users on target_users.user_id = c.user_id
    where c.deleted_at is null

    union

    select parent.id, parent.parent_category_id
    from public.transaction_categories parent
    join category_tree child on child.parent_category_id = parent.id
    join mistia_category_prune_target_users target_users on target_users.user_id = parent.user_id
    where parent.deleted_at is null
)
insert into mistia_keep_categories (id)
select distinct id
from category_tree
on conflict do nothing;

insert into mistia_keep_categories (id)
select c.id
from public.transaction_categories c
join mistia_category_prune_target_users target_users on target_users.user_id = c.user_id
where c.deleted_at is null
  and c.is_system = false
on conflict do nothing;

update public.transaction_categories c
set
    deleted_at = timezone('utc'::text, now()),
    updated_at = timezone('utc'::text, now()),
    sync_version = c.sync_version + 1,
    last_modified_by_device_id = null
from mistia_category_prune_target_users target_users
where target_users.user_id = c.user_id
  and c.deleted_at is null
  and c.is_system = true
  and not exists (
      select 1
      from mistia_keep_categories keep
      where keep.id = c.id
  );

create unique index if not exists transaction_categories_active_system_user_key_unique
on public.transaction_categories(user_id, system_key)
where is_system = true
  and system_key is not null
  and deleted_at is null;
