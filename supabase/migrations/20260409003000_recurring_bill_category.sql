alter table public.recurring_bill_plans
  add column if not exists category_id uuid references public.transaction_categories(id) on delete set null;

create index if not exists recurring_bill_plans_category_idx
  on public.recurring_bill_plans(user_id, category_id, updated_at desc);
