create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

create table if not exists public.ledger_wallets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  kind_raw_value text not null,
  icon_symbol_name text not null,
  icon_color_hex text not null,
  currency_code text not null default 'JPY',
  opening_balance_minor bigint not null default 0,
  institution_display_name text,
  institution_preset_key text,
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.credit_card_profiles (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  issuer_name text not null default '',
  network_raw_value text not null,
  last4 text not null default '',
  credit_limit_minor bigint not null default 0,
  statement_closing_day integer not null default 25,
  payment_due_day integer not null default 10,
  notes text,
  wallet_id uuid references public.ledger_wallets(id) on delete set null,
  payment_source_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create unique index if not exists credit_card_profiles_wallet_id_unique
  on public.credit_card_profiles(wallet_id)
  where deleted_at is null;

create table if not exists public.transaction_categories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  kind_raw_value text not null,
  icon_symbol_name text not null,
  icon_color_hex text not null,
  system_key text,
  is_system boolean not null default false,
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.ledger_transactions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary_kind_raw_value text not null,
  transfer_subtype_raw_value text,
  debt_intent_raw_value text,
  entry_status_raw_value text not null,
  title text not null default '',
  note text,
  amount_minor bigint not null,
  occurred_at timestamptz not null,
  counterparty_name text,
  normalized_counterparty_key text,
  source_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  destination_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  category_id uuid references public.transaction_categories(id) on delete set null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.budget_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid references public.transaction_categories(id) on delete set null,
  month_anchor timestamptz not null,
  limit_minor bigint not null,
  rollover_enabled boolean not null default false,
  currency_code text not null default 'JPY',
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.savings_goals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon_symbol_name text not null,
  target_minor bigint not null,
  current_saved_minor bigint not null default 0,
  target_date timestamptz not null,
  linked_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  currency_code text not null default 'JPY',
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.recurring_bill_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon_symbol_name text not null,
  amount_minor bigint,
  due_day integer not null,
  frequency_months integer not null default 1,
  payment_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  currency_code text not null default 'JPY',
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.installment_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon_symbol_name text not null,
  amount_per_cycle_minor bigint not null,
  due_day integer not null,
  total_cycles integer,
  frequency_months integer not null default 1,
  payment_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  currency_code text not null default 'JPY',
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create table if not exists public.due_occurrence_records (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_kind_raw_value text not null,
  source_id uuid not null,
  selected_month_key text not null,
  scheduled_date timestamptz not null,
  amount_minor_snapshot bigint,
  status_raw_value text not null,
  paid_at timestamptz,
  linked_transaction_id uuid,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz
);

create index if not exists ledger_wallets_user_id_idx on public.ledger_wallets(user_id, updated_at desc);
create index if not exists credit_card_profiles_user_id_idx on public.credit_card_profiles(user_id, updated_at desc);
create index if not exists transaction_categories_user_id_idx on public.transaction_categories(user_id, updated_at desc);
create index if not exists ledger_transactions_user_id_idx on public.ledger_transactions(user_id, updated_at desc);
create index if not exists budget_plans_user_id_idx on public.budget_plans(user_id, updated_at desc);
create index if not exists savings_goals_user_id_idx on public.savings_goals(user_id, updated_at desc);
create index if not exists recurring_bill_plans_user_id_idx on public.recurring_bill_plans(user_id, updated_at desc);
create index if not exists installment_plans_user_id_idx on public.installment_plans(user_id, updated_at desc);
create index if not exists due_occurrence_records_user_id_idx on public.due_occurrence_records(user_id, updated_at desc);

drop trigger if exists ledger_wallets_set_updated_at on public.ledger_wallets;
create trigger ledger_wallets_set_updated_at before update on public.ledger_wallets
for each row execute function public.set_updated_at();

drop trigger if exists credit_card_profiles_set_updated_at on public.credit_card_profiles;
create trigger credit_card_profiles_set_updated_at before update on public.credit_card_profiles
for each row execute function public.set_updated_at();

drop trigger if exists transaction_categories_set_updated_at on public.transaction_categories;
create trigger transaction_categories_set_updated_at before update on public.transaction_categories
for each row execute function public.set_updated_at();

drop trigger if exists ledger_transactions_set_updated_at on public.ledger_transactions;
create trigger ledger_transactions_set_updated_at before update on public.ledger_transactions
for each row execute function public.set_updated_at();

drop trigger if exists budget_plans_set_updated_at on public.budget_plans;
create trigger budget_plans_set_updated_at before update on public.budget_plans
for each row execute function public.set_updated_at();

drop trigger if exists savings_goals_set_updated_at on public.savings_goals;
create trigger savings_goals_set_updated_at before update on public.savings_goals
for each row execute function public.set_updated_at();

drop trigger if exists recurring_bill_plans_set_updated_at on public.recurring_bill_plans;
create trigger recurring_bill_plans_set_updated_at before update on public.recurring_bill_plans
for each row execute function public.set_updated_at();

drop trigger if exists installment_plans_set_updated_at on public.installment_plans;
create trigger installment_plans_set_updated_at before update on public.installment_plans
for each row execute function public.set_updated_at();

drop trigger if exists due_occurrence_records_set_updated_at on public.due_occurrence_records;
create trigger due_occurrence_records_set_updated_at before update on public.due_occurrence_records
for each row execute function public.set_updated_at();

alter table public.ledger_wallets enable row level security;
alter table public.credit_card_profiles enable row level security;
alter table public.transaction_categories enable row level security;
alter table public.ledger_transactions enable row level security;
alter table public.budget_plans enable row level security;
alter table public.savings_goals enable row level security;
alter table public.recurring_bill_plans enable row level security;
alter table public.installment_plans enable row level security;
alter table public.due_occurrence_records enable row level security;

create policy "wallets owned by current user" on public.ledger_wallets
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "credit card profiles owned by current user" on public.credit_card_profiles
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "categories owned by current user" on public.transaction_categories
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "transactions owned by current user" on public.ledger_transactions
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "budget plans owned by current user" on public.budget_plans
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "savings goals owned by current user" on public.savings_goals
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "recurring bill plans owned by current user" on public.recurring_bill_plans
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "installment plans owned by current user" on public.installment_plans
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "due occurrence records owned by current user" on public.due_occurrence_records
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
