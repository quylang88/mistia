alter table public.transaction_categories
  add column if not exists family_budget_spending_enabled boolean not null default false;

alter table public.budget_plans
  add column if not exists category_id_snapshot uuid,
  add column if not exists category_name_snapshot text,
  add column if not exists category_name_english_snapshot text,
  add column if not exists category_name_japanese_snapshot text,
  add column if not exists category_path_snapshot text,
  add column if not exists category_path_english_snapshot text,
  add column if not exists category_path_japanese_snapshot text,
  add column if not exists category_icon_symbol_name_snapshot text,
  add column if not exists category_color_hex_snapshot text,
  add column if not exists category_parent_id_snapshot uuid,
  add column if not exists category_parent_name_snapshot text,
  add column if not exists category_parent_name_english_snapshot text,
  add column if not exists category_parent_name_japanese_snapshot text,
  add column if not exists category_parent_icon_symbol_name_snapshot text,
  add column if not exists category_parent_color_hex_snapshot text,
  add column if not exists category_hierarchy_role_snapshot_raw_value text,
  add column if not exists category_is_parent_snapshot boolean,
  add column if not exists includes_family_spending boolean not null default false;

update public.budget_plans b
set
  category_id_snapshot = coalesce(b.category_id_snapshot, c.id),
  category_name_snapshot = coalesce(b.category_name_snapshot, c.name),
  category_name_english_snapshot = coalesce(b.category_name_english_snapshot, c.name_english),
  category_name_japanese_snapshot = coalesce(b.category_name_japanese_snapshot, c.name_japanese),
  category_icon_symbol_name_snapshot = coalesce(b.category_icon_symbol_name_snapshot, c.icon_symbol_name),
  category_color_hex_snapshot = coalesce(b.category_color_hex_snapshot, c.icon_color_hex),
  category_parent_id_snapshot = coalesce(b.category_parent_id_snapshot, p.id),
  category_parent_name_snapshot = coalesce(b.category_parent_name_snapshot, p.name),
  category_parent_name_english_snapshot = coalesce(b.category_parent_name_english_snapshot, p.name_english),
  category_parent_name_japanese_snapshot = coalesce(b.category_parent_name_japanese_snapshot, p.name_japanese),
  category_parent_icon_symbol_name_snapshot = coalesce(b.category_parent_icon_symbol_name_snapshot, p.icon_symbol_name),
  category_parent_color_hex_snapshot = coalesce(b.category_parent_color_hex_snapshot, p.icon_color_hex),
  category_hierarchy_role_snapshot_raw_value = coalesce(b.category_hierarchy_role_snapshot_raw_value, c.hierarchy_role_raw_value),
  category_is_parent_snapshot = coalesce(
    b.category_is_parent_snapshot,
    c.parent_category_id is null and coalesce(c.hierarchy_role_raw_value, 'parent') = 'parent'
  ),
  category_path_snapshot = coalesce(
    b.category_path_snapshot,
    case when p.id is null then c.name else p.name || ' / ' || c.name end
  ),
  category_path_english_snapshot = coalesce(
    b.category_path_english_snapshot,
    case when p.id is null then c.name_english else p.name_english || ' / ' || c.name_english end
  ),
  category_path_japanese_snapshot = coalesce(
    b.category_path_japanese_snapshot,
    case when p.id is null then c.name_japanese else p.name_japanese || ' / ' || c.name_japanese end
  )
from public.transaction_categories c
left join public.transaction_categories p on p.id = c.parent_category_id
where b.category_id = c.id;
