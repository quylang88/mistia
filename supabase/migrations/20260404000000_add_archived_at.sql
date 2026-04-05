alter table public.ledger_wallets
  add column if not exists archived_at timestamptz;

alter table public.transaction_categories
  add column if not exists archived_at timestamptz;

alter table public.ledger_transactions
  add column if not exists is_archived boolean not null default false,
  add column if not exists archived_at timestamptz;
