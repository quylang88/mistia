-- Pending settlements live outside debt/loan records. Wallet movement still
-- comes from ledger_transactions; settlement rows keep receivable/payable state.

alter table public.ledger_transactions
  add column if not exists settlement_group_id uuid,
  add column if not exists settlement_obligation_id uuid,
  add column if not exists settlement_role_raw_value text,
  add column if not exists reporting_expense_minor bigint,
  add column if not exists reporting_income_minor bigint;

create table if not exists public.settlement_groups (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind_raw_value text not null,
  status_raw_value text not null default 'open',
  title text not null default '',
  currency_code text not null default 'JPY',
  occurred_at timestamptz not null,
  total_minor bigint not null default 0 check (total_minor >= 0),
  expected_minor bigint not null default 0 check (expected_minor >= 0),
  settled_minor bigint not null default 0 check (settled_minor >= 0),
  organizer_user_id uuid references auth.users(id) on delete set null,
  note text,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid,
  constraint settlement_groups_kind_check
    check (kind_raw_value in ('resale', 'sharedExpense')),
  constraint settlement_groups_status_check
    check (status_raw_value in ('open', 'partiallySettled', 'settled')),
  constraint settlement_groups_settled_not_above_expected
    check (settled_minor <= expected_minor)
);

create table if not exists public.settlement_obligations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.settlement_groups(id) on delete cascade,
  counterparty_name text not null default '',
  normalized_counterparty_key text,
  member_user_id uuid references auth.users(id) on delete set null,
  direction_raw_value text not null,
  expected_minor bigint not null default 0 check (expected_minor >= 0),
  settled_minor bigint not null default 0 check (settled_minor >= 0),
  preferred_wallet_id uuid references public.ledger_wallets(id) on delete set null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid,
  constraint settlement_obligations_direction_check
    check (direction_raw_value in ('receivable', 'payable')),
  constraint settlement_obligations_settled_not_above_expected
    check (settled_minor <= expected_minor)
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ledger_transactions_settlement_group_id_fkey'
      and conrelid = 'public.ledger_transactions'::regclass
  ) then
    alter table public.ledger_transactions
      add constraint ledger_transactions_settlement_group_id_fkey
      foreign key (settlement_group_id)
      references public.settlement_groups(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'ledger_transactions_settlement_obligation_id_fkey'
      and conrelid = 'public.ledger_transactions'::regclass
  ) then
    alter table public.ledger_transactions
      add constraint ledger_transactions_settlement_obligation_id_fkey
      foreign key (settlement_obligation_id)
      references public.settlement_obligations(id)
      on delete set null;
  end if;
end $$;

create index if not exists settlement_groups_user_id_idx
  on public.settlement_groups(user_id, updated_at desc);

create index if not exists settlement_groups_status_idx
  on public.settlement_groups(user_id, status_raw_value, updated_at desc)
  where deleted_at is null;

create index if not exists settlement_obligations_user_id_idx
  on public.settlement_obligations(user_id, updated_at desc);

create index if not exists settlement_obligations_group_id_idx
  on public.settlement_obligations(group_id, updated_at desc);

create index if not exists settlement_obligations_open_idx
  on public.settlement_obligations(user_id, direction_raw_value, updated_at desc)
  where deleted_at is null and settled_minor < expected_minor;

create index if not exists ledger_transactions_settlement_group_idx
  on public.ledger_transactions(settlement_group_id)
  where settlement_group_id is not null;

create index if not exists ledger_transactions_settlement_obligation_idx
  on public.ledger_transactions(settlement_obligation_id)
  where settlement_obligation_id is not null;

drop trigger if exists settlement_groups_set_updated_at on public.settlement_groups;
create trigger settlement_groups_set_updated_at
before update on public.settlement_groups
for each row execute function public.set_updated_at();

drop trigger if exists settlement_obligations_set_updated_at on public.settlement_obligations;
create trigger settlement_obligations_set_updated_at
before update on public.settlement_obligations
for each row execute function public.set_updated_at();

grant select, insert, update, delete on table public.settlement_groups to authenticated;
grant select, insert, update, delete on table public.settlement_obligations to authenticated;
grant select, insert, update, delete on table public.settlement_groups to service_role;
grant select, insert, update, delete on table public.settlement_obligations to service_role;

alter table public.settlement_groups enable row level security;
alter table public.settlement_obligations enable row level security;

drop policy if exists "settlement_groups_owned_all" on public.settlement_groups;
create policy "settlement_groups_owned_all"
on public.settlement_groups
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "settlement_groups_family_select" on public.settlement_groups;
create policy "settlement_groups_family_select"
on public.settlement_groups
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

drop policy if exists "settlement_obligations_owned_all" on public.settlement_obligations;
create policy "settlement_obligations_owned_all"
on public.settlement_obligations
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "settlement_obligations_family_select" on public.settlement_obligations;
create policy "settlement_obligations_family_select"
on public.settlement_obligations
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

create or replace function public.user_has_synced_finance_data(
    p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from public.ledger_wallets where user_id = p_user_id limit 1)
        or exists (select 1 from public.credit_card_profiles where user_id = p_user_id limit 1)
        or exists (select 1 from public.transaction_categories where user_id = p_user_id limit 1)
        or exists (select 1 from public.settlement_groups where user_id = p_user_id limit 1)
        or exists (select 1 from public.settlement_obligations where user_id = p_user_id limit 1)
        or exists (select 1 from public.ledger_transactions where user_id = p_user_id limit 1)
        or exists (select 1 from public.budget_plans where user_id = p_user_id limit 1)
        or exists (select 1 from public.savings_goals where user_id = p_user_id limit 1)
        or exists (select 1 from public.recurring_bill_plans where user_id = p_user_id limit 1)
        or exists (select 1 from public.installment_plans where user_id = p_user_id limit 1)
        or exists (select 1 from public.due_occurrence_records where user_id = p_user_id limit 1);
$$;

revoke all on function public.user_has_synced_finance_data(uuid) from public;
