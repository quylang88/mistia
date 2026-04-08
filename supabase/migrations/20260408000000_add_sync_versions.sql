alter table public.ledger_wallets
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.credit_card_profiles
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.transaction_categories
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.ledger_transactions
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.budget_plans
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.savings_goals
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.recurring_bill_plans
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.installment_plans
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;

alter table public.due_occurrence_records
  add column if not exists sync_version bigint not null default 1,
  add column if not exists last_modified_by_device_id uuid;
