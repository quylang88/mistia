alter table public.transaction_categories
  add column if not exists is_favorite boolean not null default false;

create index if not exists transaction_categories_favorite_idx
  on public.transaction_categories(user_id, kind_raw_value, is_favorite, updated_at desc);
