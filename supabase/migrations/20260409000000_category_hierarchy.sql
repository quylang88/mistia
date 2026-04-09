alter table public.transaction_categories
  add column if not exists parent_category_id uuid references public.transaction_categories(id) on delete set null;

alter table public.transaction_categories
  add column if not exists hierarchy_role_raw_value text;

create index if not exists transaction_categories_parent_category_idx
  on public.transaction_categories(user_id, parent_category_id, updated_at desc);
