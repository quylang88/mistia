create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public.mistia_sha1_hex(p_value text)
returns text
language plpgsql
immutable
as $$
declare
    v_result text;
begin
    if to_regprocedure('extensions.digest(text,text)') is not null then
        execute 'select encode(extensions.digest($1, ''sha1''), ''hex'')'
        into v_result
        using p_value;
    elsif to_regprocedure('public.digest(text,text)') is not null then
        execute 'select encode(public.digest($1, ''sha1''), ''hex'')'
        into v_result
        using p_value;
    else
        raise exception 'pgcrypto.digest(text,text) is not available';
    end if;

    return v_result;
end;
$$;

create or replace function public.mistia_stable_uuid(p_value text)
returns uuid
language sql
immutable
as $$
    with hashed as (
        select public.mistia_sha1_hex(p_value) as value
    )
    select (
        substr(value, 1, 12)
        || '5'
        || substr(value, 14, 3)
        || lpad(to_hex((get_byte(decode(substr(value, 17, 2), 'hex'), 0) & 63) | 128), 2, '0')
        || substr(value, 19, 14)
    )::uuid
    from hashed;
$$;

create temporary table mistia_system_category_targets on commit drop as
with ranked as (
    select
        c.*,
        public.mistia_stable_uuid(
            'vn.com.quyln.mistia.system-category.cloud.'
            || lower(c.user_id::text)
            || '.'
            || lower(public.mistia_stable_uuid('vn.com.quyln.mistia.system-category.' || c.system_key)::text)
        ) as target_id,
        row_number() over (
            partition by c.user_id, c.system_key
            order by
                c.updated_at desc,
                c.created_at desc,
                c.id
        ) as row_number
    from public.transaction_categories c
    where c.is_system = true
      and c.system_key is not null
      and c.deleted_at is null
)
select *
from ranked
where row_number = 1;

create temporary table mistia_system_category_id_map on commit drop as
select
    c.id as old_id,
    t.target_id as new_id
from public.transaction_categories c
join mistia_system_category_targets t
  on t.user_id = c.user_id
 and t.system_key = c.system_key
where c.is_system = true
  and c.system_key is not null
  and c.id <> t.target_id;

insert into public.transaction_categories (
    id,
    user_id,
    name,
    kind_raw_value,
    icon_symbol_name,
    icon_color_hex,
    is_favorite,
    parent_category_id,
    hierarchy_role_raw_value,
    system_key,
    is_system,
    sort_order,
    is_archived,
    archived_at,
    created_at,
    updated_at,
    deleted_at,
    sync_version,
    last_modified_by_device_id
)
select
    target_id,
    user_id,
    name,
    kind_raw_value,
    icon_symbol_name,
    icon_color_hex,
    is_favorite,
    null,
    hierarchy_role_raw_value,
    system_key,
    true,
    sort_order,
    is_archived,
    archived_at,
    created_at,
    updated_at,
    null,
    sync_version + 1,
    last_modified_by_device_id
from mistia_system_category_targets
on conflict (id)
do update set
    user_id = excluded.user_id,
    name = excluded.name,
    kind_raw_value = excluded.kind_raw_value,
    icon_symbol_name = excluded.icon_symbol_name,
    icon_color_hex = excluded.icon_color_hex,
    is_favorite = excluded.is_favorite,
    hierarchy_role_raw_value = excluded.hierarchy_role_raw_value,
    system_key = excluded.system_key,
    is_system = true,
    sort_order = excluded.sort_order,
    is_archived = excluded.is_archived,
    archived_at = excluded.archived_at,
    deleted_at = null,
    sync_version = greatest(public.transaction_categories.sync_version, excluded.sync_version),
    last_modified_by_device_id = excluded.last_modified_by_device_id;

update public.transaction_categories c
set
    parent_category_id = parent_target.target_id,
    sync_version = c.sync_version + 1
from mistia_system_category_targets child_target
join public.transaction_categories source_parent
  on source_parent.id = child_target.parent_category_id
join mistia_system_category_targets parent_target
  on parent_target.user_id = source_parent.user_id
 and parent_target.system_key = source_parent.system_key
where c.id = child_target.target_id
  and c.parent_category_id is distinct from parent_target.target_id;

update public.transaction_categories c
set
    parent_category_id = m.new_id,
    sync_version = c.sync_version + 1
from mistia_system_category_id_map m
where c.parent_category_id = m.old_id;

update public.ledger_transactions t
set
    category_id = m.new_id,
    sync_version = t.sync_version + 1
from mistia_system_category_id_map m
where t.category_id = m.old_id;

update public.budget_plans b
set
    category_id = m.new_id,
    sync_version = b.sync_version + 1
from mistia_system_category_id_map m
where b.category_id = m.old_id;

update public.recurring_bill_plans r
set
    category_id = m.new_id,
    sync_version = r.sync_version + 1
from mistia_system_category_id_map m
where r.category_id = m.old_id;

update public.family_permission_requests r
set resource_id = m.new_id
from mistia_system_category_id_map m
where r.resource_type = 'category'
  and r.resource_id = m.old_id;

update public.family_permission_grants g
set resource_id = m.new_id
from mistia_system_category_id_map m
where g.resource_type = 'category'
  and g.resource_id = m.old_id;

update public.family_notifications n
set
    resource_id = m.new_id,
    sync_version = n.sync_version + 1
from mistia_system_category_id_map m
where n.resource_type = 'category'
  and n.resource_id = m.old_id;

update public.transaction_categories c
set
    deleted_at = timezone('utc'::text, now()),
    sync_version = c.sync_version + 1
from mistia_system_category_id_map m
where c.id = m.old_id
  and c.deleted_at is null;

create unique index if not exists transaction_categories_active_system_user_key_unique
on public.transaction_categories(user_id, system_key)
where is_system = true
  and system_key is not null
  and deleted_at is null;

drop function if exists public.mistia_stable_uuid(text);
drop function if exists public.mistia_sha1_hex(text);
