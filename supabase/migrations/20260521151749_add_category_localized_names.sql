alter table public.transaction_categories
  add column if not exists name_english text,
  add column if not exists name_japanese text;

create temporary table mistia_category_language_duplicate_map on commit drop as
with duplicate_candidates as (
  select
    c.*,
    row_number() over (
      partition by c.user_id, c.system_key
      order by
        case when c.deleted_at is null then 0 else 1 end,
        case when c.is_archived is false then 0 else 1 end,
        c.sync_version desc,
        c.updated_at desc,
        c.created_at asc,
        c.id asc
    ) as keep_rank
  from public.transaction_categories c
  where c.system_key is not null
),
keepers as (
  select user_id, system_key, id as keep_id
  from duplicate_candidates
  where keep_rank = 1
),
duplicates as (
  select c.user_id, c.system_key, c.id as old_id, k.keep_id
  from duplicate_candidates c
  join keepers k
    on k.user_id = c.user_id
   and k.system_key = c.system_key
  where c.id <> k.keep_id
)
select * from duplicates;

with duplicate_names as (
  select
    m.keep_id,
    max(c.name) filter (
      where c.name ~ '^[ -~]+$'
    ) as english_name,
    max(c.name) filter (
      where c.name ~ '[ぁ-んァ-ン一-龯]'
    ) as japanese_name
  from mistia_category_language_duplicate_map m
  join public.transaction_categories c
    on c.id = m.old_id
  group by m.keep_id
)
update public.transaction_categories c
set
  name_english = coalesce(nullif(btrim(c.name_english), ''), nullif(btrim(d.english_name), '')),
  name_japanese = coalesce(nullif(btrim(c.name_japanese), ''), nullif(btrim(d.japanese_name), '')),
  sync_version = c.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from duplicate_names d
where c.id = d.keep_id
  and (
    c.name_english is distinct from coalesce(nullif(btrim(c.name_english), ''), nullif(btrim(d.english_name), ''))
    or c.name_japanese is distinct from coalesce(nullif(btrim(c.name_japanese), ''), nullif(btrim(d.japanese_name), ''))
  );

update public.transaction_categories child
set
  parent_category_id = m.keep_id,
  sync_version = child.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where child.parent_category_id = m.old_id;

update public.ledger_transactions t
set
  category_id = m.keep_id,
  sync_version = t.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where t.category_id = m.old_id;

update public.budget_plans b
set
  category_id = m.keep_id,
  sync_version = b.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where b.category_id = m.old_id;

update public.recurring_bill_plans r
set
  category_id = m.keep_id,
  sync_version = r.sync_version + 1,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where r.category_id = m.old_id;

delete from public.family_permission_requests old_request
using mistia_category_language_duplicate_map m
where old_request.resource_type = 'category'
  and old_request.resource_id = m.old_id
  and exists (
    select 1
    from public.family_permission_requests keep_request
    where keep_request.family_id = old_request.family_id
      and keep_request.requester_user_id = old_request.requester_user_id
      and keep_request.recipient_user_id = old_request.recipient_user_id
      and keep_request.resource_type = old_request.resource_type
      and keep_request.resource_id = m.keep_id
      and keep_request.permission_scope = old_request.permission_scope
  );

update public.family_permission_requests r
set
  resource_id = m.keep_id,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where r.resource_type = 'category'
  and r.resource_id = m.old_id;

delete from public.family_permission_grants old_grant
using mistia_category_language_duplicate_map m
where old_grant.resource_type = 'category'
  and old_grant.resource_id = m.old_id
  and exists (
    select 1
    from public.family_permission_grants keep_grant
    where keep_grant.grantee_user_id = old_grant.grantee_user_id
      and keep_grant.owner_user_id = old_grant.owner_user_id
      and keep_grant.resource_type = old_grant.resource_type
      and keep_grant.resource_id = m.keep_id
      and keep_grant.permission_scope = old_grant.permission_scope
  );

update public.family_permission_grants g
set
  resource_id = m.keep_id,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where g.resource_type = 'category'
  and g.resource_id = m.old_id;

update public.family_notifications n
set
  resource_id = m.keep_id,
  updated_at = timezone('utc'::text, now())
from mistia_category_language_duplicate_map m
where n.resource_type = 'category'
  and n.resource_id = m.old_id;

delete from public.transaction_categories c
using mistia_category_language_duplicate_map m
where c.id = m.old_id;
