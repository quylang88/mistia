-- 20260403000000_mistia_sync.sql

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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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
  deleted_at timestamptz,
  sync_version bigint not null default 1,
  last_modified_by_device_id uuid
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


-- 20260404000000_add_archived_at.sql

alter table public.ledger_wallets
  add column if not exists archived_at timestamptz;

alter table public.transaction_categories
  add column if not exists archived_at timestamptz;

alter table public.ledger_transactions
  add column if not exists is_archived boolean not null default false,
  add column if not exists archived_at timestamptz;


-- 20260408000000_add_sync_versions.sql

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


-- 20260409000000_category_hierarchy.sql

alter table public.transaction_categories
  add column if not exists parent_category_id uuid references public.transaction_categories(id) on delete set null;

alter table public.transaction_categories
  add column if not exists hierarchy_role_raw_value text;

create index if not exists transaction_categories_parent_category_idx
  on public.transaction_categories(user_id, parent_category_id, updated_at desc);


-- 20260409001000_create_user_profiles.sql

create table if not exists public.user_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default '',
    avatar_url text,
    birthday date,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

drop trigger if exists user_profiles_set_updated_at on public.user_profiles;
create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row
execute function public.set_updated_at();

alter table public.user_profiles enable row level security;

drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own"
on public.user_profiles
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    insert into public.user_profiles (
        user_id,
        display_name,
        avatar_url
    )
    values (
        new.id,
        coalesce(
            nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
            nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
            nullif(split_part(new.email, '@', 1), ''),
            'Mistia'
        ),
        nullif(
            coalesce(
                new.raw_user_meta_data ->> 'avatar_url',
                new.raw_user_meta_data ->> 'picture'
            ),
            ''
        )
    )
    on conflict (user_id) do nothing;
    return new;
end;
$$;

insert into public.user_profiles (
    user_id,
    display_name,
    avatar_url,
    created_at,
    updated_at
)
select
    users.id,
    coalesce(
        nullif(trim(users.raw_user_meta_data ->> 'display_name'), ''),
        nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
        nullif(split_part(users.email, '@', 1), ''),
        'Mistia'
    ),
    nullif(
        coalesce(
            users.raw_user_meta_data ->> 'avatar_url',
            users.raw_user_meta_data ->> 'picture'
        ),
        ''
    ),
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
from auth.users as users
on conflict (user_id) do nothing;

drop trigger if exists on_auth_user_created_user_profile on auth.users;
create trigger on_auth_user_created_user_profile
after insert on auth.users
for each row
execute function public.handle_new_user_profile();

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'profile-avatars',
    'profile-avatars',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do update
set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "profile_avatars_public_read" on storage.objects;
create policy "profile_avatars_public_read"
on storage.objects
for select
to public
using (bucket_id = 'profile-avatars');

drop policy if exists "profile_avatars_insert_own" on storage.objects;
create policy "profile_avatars_insert_own"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "profile_avatars_update_own" on storage.objects;
create policy "profile_avatars_update_own"
on storage.objects
for update
to authenticated
using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "profile_avatars_delete_own" on storage.objects;
create policy "profile_avatars_delete_own"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);


-- 20260409003000_recurring_bill_category.sql

alter table public.recurring_bill_plans
  add column if not exists category_id uuid references public.transaction_categories(id) on delete set null;

create index if not exists recurring_bill_plans_category_idx
  on public.recurring_bill_plans(user_id, category_id, updated_at desc);


-- 20260410090000_category_favorites.sql

alter table public.transaction_categories
  add column if not exists is_favorite boolean not null default false;

create index if not exists transaction_categories_favorite_idx
  on public.transaction_categories(user_id, kind_raw_value, is_favorite, updated_at desc);


-- 20260410100000_create_family_tables.sql

-- ============================================================
-- Family tables: families, family_memberships, family_invites
-- ============================================================

-- 1. families
create table if not exists public.families (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists families_owner_user_id_idx on public.families(owner_user_id);

drop trigger if exists families_set_updated_at on public.families;
create trigger families_set_updated_at before update on public.families
for each row execute function public.set_updated_at();

-- 2. family_memberships
create table if not exists public.family_memberships (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'viewer',
    can_view_family_dashboard boolean not null default true,
    can_view_others boolean not null default false,
    can_edit_others boolean not null default false,
    can_view_wallets boolean not null default true,
    can_view_debts boolean not null default true,
    can_view_kids boolean not null default false,
    can_edit_kids boolean not null default false,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

-- One membership per user per family
create unique index if not exists family_memberships_family_user_unique
    on public.family_memberships(family_id, user_id);

create index if not exists family_memberships_user_id_idx on public.family_memberships(user_id);
create index if not exists family_memberships_family_id_idx on public.family_memberships(family_id);

drop trigger if exists family_memberships_set_updated_at on public.family_memberships;
create trigger family_memberships_set_updated_at before update on public.family_memberships
for each row execute function public.set_updated_at();

-- 3. family_invites
create table if not exists public.family_invites (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    code text not null,
    created_by_user_id uuid not null references auth.users(id) on delete cascade,
    default_role text not null default 'viewer',
    expires_at timestamptz not null,
    accepted_at timestamptz,
    accepted_by_user_id uuid references auth.users(id) on delete set null,
    revoked_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

create unique index if not exists family_invites_code_unique on public.family_invites(code);
create index if not exists family_invites_family_id_idx on public.family_invites(family_id);

drop trigger if exists family_invites_set_updated_at on public.family_invites;
create trigger family_invites_set_updated_at before update on public.family_invites
for each row execute function public.set_updated_at();

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.families enable row level security;
alter table public.family_memberships enable row level security;
alter table public.family_invites enable row level security;

-- ---------- families ----------

-- Owner can do everything on their own family
create policy "families_owner_all"
on public.families
for all
to authenticated
using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);

-- Members can read the family they belong to
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    exists (
        select 1 from public.family_memberships fm
        where fm.family_id = families.id
          and fm.user_id = auth.uid()
    )
);

-- ---------- family_memberships ----------

-- Members can view all memberships in their family
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    exists (
        select 1 from public.family_memberships my_fm
        where my_fm.family_id = family_memberships.family_id
          and my_fm.user_id = auth.uid()
    )
);

-- Family owner can insert memberships (add members)
create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (
    exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
    )
    or family_memberships.user_id = auth.uid()
);

-- Family owner can update memberships (change roles/permissions)
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (
    exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
    )
)
with check (
    exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
    )
);

-- Family owner can remove memberships
create policy "family_memberships_owner_delete"
on public.family_memberships
for delete
to authenticated
using (
    exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
    )
    or family_memberships.user_id = auth.uid()
);

-- ---------- family_invites ----------

-- Owner can manage invites for their family
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (
    exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
    )
)
with check (
    exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
    )
);

-- Anyone authenticated can read an invite by code (for joining)
create policy "family_invites_read_by_code"
on public.family_invites
for select
to authenticated
using (true);

-- ---------- user_profiles: allow family members to read each other ----------

drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_family_members"
on public.user_profiles
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships my_fm
        join public.family_memberships their_fm
          on my_fm.family_id = their_fm.family_id
        where my_fm.user_id = auth.uid()
          and their_fm.user_id = user_profiles.user_id
    )
);

-- ============================================================
-- Update existing finance table RLS to allow family access
-- ============================================================

-- Wallets: family members with view permission can read
drop policy if exists "wallets_family_member_select" on public.ledger_wallets;
create policy "wallets_family_member_select"
on public.ledger_wallets
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships my_fm
        join public.family_memberships their_fm
          on my_fm.family_id = their_fm.family_id
        where my_fm.user_id = auth.uid()
          and their_fm.user_id = ledger_wallets.user_id
          and my_fm.can_view_wallets = true
    )
);

-- Transactions: family members with view permission can read
drop policy if exists "transactions_family_member_select" on public.ledger_transactions;
create policy "transactions_family_member_select"
on public.ledger_transactions
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships my_fm
        join public.family_memberships their_fm
          on my_fm.family_id = their_fm.family_id
        where my_fm.user_id = auth.uid()
          and their_fm.user_id = ledger_transactions.user_id
          and my_fm.can_view_others = true
    )
);

-- Categories: family members can read
drop policy if exists "categories_family_member_select" on public.transaction_categories;
create policy "categories_family_member_select"
on public.transaction_categories
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships my_fm
        join public.family_memberships their_fm
          on my_fm.family_id = their_fm.family_id
        where my_fm.user_id = auth.uid()
          and their_fm.user_id = transaction_categories.user_id
          and my_fm.can_view_others = true
    )
);


-- 20260410110000_fix_family_rls_recursion.sql

-- ============================================================
-- Fix: Self-referencing RLS on family_memberships causes 500
--
-- Problem: family_memberships_member_select policy queries
-- family_memberships inside its own RLS → infinite recursion.
-- Also affects user_profiles_select_family_members and all
-- other policies that join family_memberships.
--
-- Solution: Use a SECURITY DEFINER helper function that
-- bypasses RLS when checking family membership.
-- ============================================================

-- 1. Helper: check if current user belongs to a given family (bypasses RLS)
create or replace function public.is_family_member(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.family_memberships
        where family_id = p_family_id
          and user_id = auth.uid()
    );
$$;

-- 2. Helper: get all family_ids the current user belongs to (bypasses RLS)
create or replace function public.my_family_ids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
    select family_id from public.family_memberships
    where user_id = auth.uid();
$$;

-- 3. Helper: get all user_ids that share a family with the current user (bypasses RLS)
create or replace function public.my_family_member_user_ids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
    select distinct fm.user_id
    from public.family_memberships fm
    where fm.family_id in (
        select family_id from public.family_memberships
        where user_id = auth.uid()
    );
$$;

-- ============================================================
-- Re-create family_memberships policies using the helper
-- ============================================================

-- SELECT: members can view all memberships in their family
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    public.is_family_member(family_id)
);

-- ============================================================
-- Re-create user_profiles SELECT policy using the helper
-- ============================================================

drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_family_members"
on public.user_profiles
for select
to authenticated
using (
    auth.uid() = user_id
    or user_id in (select public.my_family_member_user_ids())
);

-- ============================================================
-- Re-create finance table policies using the helper
-- ============================================================

-- Wallets
drop policy if exists "wallets_family_member_select" on public.ledger_wallets;
create policy "wallets_family_member_select"
on public.ledger_wallets
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships fm
        where fm.family_id in (select public.my_family_ids())
          and fm.user_id = ledger_wallets.user_id
          and fm.can_view_wallets = true
    )
);

-- Transactions
drop policy if exists "transactions_family_member_select" on public.ledger_transactions;
create policy "transactions_family_member_select"
on public.ledger_transactions
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships fm
        where fm.family_id in (select public.my_family_ids())
          and fm.user_id = ledger_transactions.user_id
          and fm.can_view_others = true
    )
);

-- Categories
drop policy if exists "categories_family_member_select" on public.transaction_categories;
create policy "categories_family_member_select"
on public.transaction_categories
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.family_memberships fm
        where fm.family_id in (select public.my_family_ids())
          and fm.user_id = transaction_categories.user_id
          and fm.can_view_others = true
    )
);

-- ============================================================
-- Re-create families member SELECT using the helper
-- ============================================================

drop policy if exists "families_member_select" on public.families;
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    public.is_family_member(id)
);


-- 20260411010000_fix_family_membership_rls.sql

-- ============================================================
-- Fix: Family Membership RLS policies
--
-- This migration fixes the "new row violates policy" error
-- by allowing users to insert their own initial membership
-- and by using a non-recursive owner check helper.
-- ============================================================

-- 1. Helper: check if current user is owner of a given family (bypasses RLS)
create or replace function public.is_family_owner(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.families
        where id = p_family_id
          and owner_user_id = auth.uid()
    );
$$;

-- 2. family_memberships: INSERT
-- Family owner can add members OR any user can insert their OWN initial membership
drop policy if exists "family_memberships_owner_insert" on public.family_memberships;
create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (
    public.is_family_owner(family_id)
    or user_id = auth.uid()
);

-- 3. family_memberships: UPDATE
-- Family owner can change roles/permissions
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (
    public.is_family_owner(family_id)
)
with check (
    public.is_family_owner(family_id)
);

-- 4. family_memberships: DELETE
-- Family owner can remove members OR any user can remove THEMSELVES
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;
create policy "family_memberships_owner_delete"
on public.family_memberships
for delete
to authenticated
using (
    public.is_family_owner(family_id)
    or user_id = auth.uid()
);


-- 20260411020000_fix_family_membership_rls_v2.sql

-- ============================================================
-- Fix: Family Membership RLS policies (REVISION 2)
--
-- This migration adopts a more robust approach to RLS:
-- 1. Direct "self" access for SELECT/INSERT/DELETE based on auth.uid() = user_id.
-- 2. Membership-based "others" access for SELECT via helper.
-- 3. Ownership-based access for UPDATE/DELETE via helper.
-- ============================================================

-- A. Cleanup existing policies to avoid conflicts
drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "family_memberships_owner_insert" on public.family_memberships;
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;

-- B. Re-ensure helper functions are current and robust
create or replace function public.is_family_member(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.family_memberships
        where family_id = p_family_id
          and user_id = auth.uid()
    );
$$;

create or replace function public.is_family_owner(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.families
        where id = p_family_id
          and owner_user_id = auth.uid()
    );
$$;

-- C. Define new policies

-- 1. SELECT: Users can always see their own membership
create policy "family_memberships_self_select"
on public.family_memberships
for select
to authenticated
using (user_id = auth.uid());

-- 2. SELECT: Members can view all memberships in their family
create policy "family_memberships_others_select"
on public.family_memberships
for select
to authenticated
using (public.is_family_member(family_id));

-- 3. INSERT: Users can always insert their own membership (initial creating or joining)
create policy "family_memberships_self_insert"
on public.family_memberships
for insert
to authenticated
with check (user_id = auth.uid());

-- 4. INSERT: Family owners can manually add other members
create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (public.is_family_owner(family_id));

-- 5. UPDATE: Family owners can change roles/permissions
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (public.is_family_owner(family_id))
with check (public.is_family_owner(family_id));

-- 6. DELETE: Users can remove themselves OR owners can remove others
create policy "family_memberships_management_delete"
on public.family_memberships
for delete
to authenticated
using (
    user_id = auth.uid()
    or public.is_family_owner(family_id)
);


-- 20260411030000_allow_family_select_via_invite.sql

-- ============================================================
-- Fix: Allow viewing families via active invite codes
--
-- Problem: Join process fails with "Family not found" because
-- non-members cannot see the family row they are trying to join.
--
-- Solution: Add a SELECT policy to the families table that grants
-- access if any active, non-expired invite exists for that family.
-- ============================================================

drop policy if exists "families_invite_select" on public.families;
create policy "families_invite_select"
on public.families
for select
to authenticated
using (
    exists (
        select 1 from public.family_invites fi
        where fi.family_id = id
          and fi.accepted_at is null
          and fi.revoked_at is null
          and fi.expires_at >= now()
    )
);


-- 20260411040000_fix_family_invites_recursion.sql

-- ============================================================
-- Fix: RLS Recursion between families and family_invites
--
-- Problem: families policy queries family_invites, and
-- family_invites policy queries families -> infinite loop.
--
-- Solution: Use SECURITY DEFINER helpers to break the chain.
-- ============================================================

-- 1. Helper: check for active invites without triggering RLS (SECURITY DEFINER)
create or replace function public.has_active_invite(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1 from public.family_invites
        where family_id = p_family_id
          and accepted_at is null
          and revoked_at is null
          and expires_at >= now()
    );
$$;

-- 2. Update families policy to use the helper
drop policy if exists "families_invite_select" on public.families;
create policy "families_invite_select"
on public.families
for select
to authenticated
using (public.has_active_invite(id));

-- 3. Update family_invites policy to use is_family_owner helper
-- is_family_owner is already SECURITY DEFINER, so it breaks the chain
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (public.is_family_owner(family_id))
with check (public.is_family_owner(family_id));


-- 20260411050000_allow_invite_acceptance.sql

-- ============================================================
-- Fix: Allow invitees to mark invites as accepted
--
-- Problem: Joining user gets "invalid response" because they
-- don't have UPDATE permission on the family_invites table,
-- causing the markInviteAccepted call to return empty rows.
--
-- Solution: Add an UPDATE policy for authenticated users that
-- allows them to accept active invites.
-- ============================================================

drop policy if exists "family_invites_accept_update" on public.family_invites;
create policy "family_invites_accept_update"
on public.family_invites
for update
to authenticated
using (
    accepted_at is null
    and revoked_at is null
    and expires_at >= now()
)
with check (
    accepted_by_user_id = auth.uid()
);


-- 20260411060000_soft_delete_family.sql

-- Add deleted_at columns for soft delete
alter table public.families add column if not exists deleted_at timestamptz;
alter table public.family_memberships add column if not exists deleted_at timestamptz;
alter table public.family_invites add column if not exists deleted_at timestamptz;

-- Update unique index to allow re-joining/re-creating after soft delete
drop index if exists public.family_memberships_family_user_unique;
create unique index family_memberships_family_user_unique
    on public.family_memberships(family_id, user_id)
    where deleted_at is null;

-- Update RLS policies to exclude soft-deleted records

-- families
drop policy if exists "families_owner_all" on public.families;
create policy "families_owner_all"
on public.families
for all
to authenticated
using (auth.uid() = owner_user_id and deleted_at is null)
with check (auth.uid() = owner_user_id and deleted_at is null);

drop policy if exists "families_member_select" on public.families;
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.family_memberships fm
        where fm.family_id = families.id
          and fm.user_id = auth.uid()
          and fm.deleted_at is null
    )
);

-- family_memberships
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.family_memberships my_fm
        where my_fm.family_id = family_memberships.family_id
          and my_fm.user_id = auth.uid()
          and my_fm.deleted_at is null
    )
);

drop policy if exists "family_memberships_owner_update" on public.family_memberships;
create policy "family_memberships_owner_update"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
)
with check (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_memberships.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
);

-- family_invites
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
)
with check (
    deleted_at is null
    and exists (
        select 1 from public.families f
        where f.id = family_invites.family_id
          and f.owner_user_id = auth.uid()
          and f.deleted_at is null
    )
);

drop policy if exists "family_invites_read_by_code" on public.family_invites;
create policy "family_invites_read_by_code"
on public.family_invites
for select
to authenticated
using (deleted_at is null);


-- 20260412000000_fix_family_memberships_policy.sql

-- Fix infinite loop in family_memberships policy
-- The previous policy caused infinite loop by referencing family_memberships table within its own policy

-- family_memberships - member select
drop policy if exists "family_memberships_member_select" on public.family_memberships;
create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and (
        user_id = auth.uid()
        or exists (
            select 1 from public.families f
            where f.id = family_memberships.family_id
              and f.owner_user_id = auth.uid()
              and f.deleted_at is null
        )
    )
);


-- 20260412000001_fix_infinite_loop_with_security_definer.sql

-- Fix infinite loop in family_memberships policy using SECURITY DEFINER function
-- The issue: circular RLS references cause infinite loops
-- Solution: Use helper functions with SECURITY DEFINER to bypass RLS recursion

-- Drop old policies first
drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "families_member_select" on public.families;

-- Drop existing functions if they exist
drop function if exists public.is_family_member(uuid) cascade;
drop function if exists public.is_family_owner(uuid) cascade;

-- Create helper functions with SECURITY DEFINER to bypass RLS
create function public.is_family_member(family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.family_memberships
    where family_memberships.family_id = $1
      and family_memberships.user_id = auth.uid()
      and family_memberships.deleted_at is null
  );
$$;

create function public.is_family_owner(family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.families
    where families.id = $1
      and families.owner_user_id = auth.uid()
      and families.deleted_at is null
  );
$$;

-- New policies using helper functions
create policy "families_member_select"
on public.families
for select
to authenticated
using (
    deleted_at is null
    and (
        auth.uid() = owner_user_id
        or public.is_family_member(id)
    )
);

create policy "family_memberships_member_select"
on public.family_memberships
for select
to authenticated
using (
    deleted_at is null
    and (
        user_id = auth.uid()
        or public.is_family_owner(family_id)
    )
);


-- 20260412000002_fix_family_rls_soft_delete.sql

-- Fix RLS policies to allow soft delete (setting deleted_at)
-- and allow members to leave families (self-update)

-- 1. Update is_family_owner to ignore deleted_at of the family
-- This allows the owner to soft-delete associated records (memberships, invites)
-- even after the family record itself has been soft-deleted.
create or replace function public.is_family_owner(family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.families
    where families.id = $1
      and families.owner_user_id = auth.uid()
  );
$$;

-- 2. families: Allow owner to update the record (including soft-delete)
-- We remove the 'deleted_at is null' check from WITH CHECK to allow setting it.
drop policy if exists "families_owner_all" on public.families;
create policy "families_owner_all"
on public.families
for all
to authenticated
using (auth.uid() = owner_user_id and deleted_at is null)
with check (auth.uid() = owner_user_id);

-- 3. family_memberships: Allow owner to manage and members to leave
-- Drop old restrictive policies
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;

-- New update policy: 
-- - Allows members to update their own membership (e.g., to leave the family)
-- - Allows family owner to update any membership in their family
-- - Removes 'deleted_at is null' from WITH CHECK to allow the actual soft-delete update.
create policy "family_memberships_update_policy"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and (user_id = auth.uid() or public.is_family_owner(family_id))
)
with check (
    user_id = auth.uid() or public.is_family_owner(family_id)
);

-- Also add a delete policy for completeness (though app uses soft-delete)
create policy "family_memberships_delete_policy"
on public.family_memberships
for delete
to authenticated
using (
    user_id = auth.uid() or public.is_family_owner(family_id)
);

-- 4. family_invites: Allow owner to soft-delete invites
drop policy if exists "family_invites_owner_all" on public.family_invites;
create policy "family_invites_owner_all"
on public.family_invites
for all
to authenticated
using (
    deleted_at is null
    and public.is_family_owner(family_id)
)
with check (
    public.is_family_owner(family_id)
);


-- 20260415000000_family_wallet_access_and_transaction_audit.sql

create table if not exists public.family_wallet_access_grants (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    grantee_user_id uuid not null references auth.users(id) on delete cascade,
    target_user_id uuid not null references auth.users(id) on delete cascade,
    granted_by_user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    revoked_at timestamptz
);

create unique index if not exists family_wallet_access_grants_active_unique
    on public.family_wallet_access_grants(family_id, grantee_user_id, target_user_id)
    where revoked_at is null;

create index if not exists family_wallet_access_grants_active_lookup_idx
    on public.family_wallet_access_grants(grantee_user_id, target_user_id, family_id)
    where revoked_at is null;

drop trigger if exists family_wallet_access_grants_set_updated_at on public.family_wallet_access_grants;
create trigger family_wallet_access_grants_set_updated_at before update on public.family_wallet_access_grants
for each row execute function public.set_updated_at();

alter table public.family_wallet_access_grants enable row level security;

alter table public.ledger_transactions
    add column if not exists created_by_user_id uuid,
    add column if not exists last_modified_by_user_id uuid;

update public.ledger_transactions
set created_by_user_id = coalesce(created_by_user_id, user_id),
    last_modified_by_user_id = coalesce(last_modified_by_user_id, user_id)
where created_by_user_id is null
   or last_modified_by_user_id is null;

alter table public.ledger_transactions
    alter column created_by_user_id set not null,
    alter column last_modified_by_user_id set not null;

do $$
begin
    alter table public.ledger_transactions
        add constraint ledger_transactions_created_by_user_id_fkey
        foreign key (created_by_user_id) references auth.users(id) on delete cascade;
exception
    when duplicate_object then null;
end $$;

do $$
begin
    alter table public.ledger_transactions
        add constraint ledger_transactions_last_modified_by_user_id_fkey
        foreign key (last_modified_by_user_id) references auth.users(id) on delete cascade;
exception
    when duplicate_object then null;
end $$;

create index if not exists ledger_transactions_created_by_user_id_idx
    on public.ledger_transactions(created_by_user_id, updated_at desc);

create index if not exists ledger_transactions_source_wallet_id_idx
    on public.ledger_transactions(source_wallet_id);

create index if not exists ledger_transactions_destination_wallet_id_idx
    on public.ledger_transactions(destination_wallet_id);

create or replace function public.is_family_owner_of_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.families f
        join public.family_memberships fm
          on fm.family_id = f.id
        where f.owner_user_id = auth.uid()
          and f.deleted_at is null
          and fm.user_id = target_user_id
          and fm.deleted_at is null
    );
$$;

create or replace function public.has_family_wallet_access(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = target_user_id
        or public.is_family_owner_of_user(target_user_id)
        or exists (
            select 1
            from public.family_wallet_access_grants g
            join public.families f
              on f.id = g.family_id
            join public.family_memberships grantee_membership
              on grantee_membership.family_id = g.family_id
             and grantee_membership.user_id = g.grantee_user_id
            join public.family_memberships target_membership
              on target_membership.family_id = g.family_id
             and target_membership.user_id = g.target_user_id
            where g.grantee_user_id = auth.uid()
              and g.target_user_id = target_user_id
              and g.revoked_at is null
              and f.deleted_at is null
              and grantee_membership.deleted_at is null
              and target_membership.deleted_at is null
        );
$$;

create or replace function public.wallet_owner_user_id(target_wallet_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select user_id
    from public.ledger_wallets
    where id = target_wallet_id
    limit 1;
$$;

create or replace function public.can_operate_wallet(target_wallet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.ledger_wallets w
        where w.id = target_wallet_id
          and public.has_family_wallet_access(w.user_id)
    );
$$;

create or replace function public.transaction_category_matches_owner(target_category_id uuid, owner_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        target_category_id is null
        or exists (
            select 1
            from public.transaction_categories c
            where c.id = target_category_id
              and c.user_id = owner_user_id
        );
$$;

create or replace function public.can_read_transaction(
    owner_user_id uuid,
    created_by_user_id uuid,
    source_wallet_id uuid,
    destination_wallet_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = owner_user_id
        or auth.uid() = created_by_user_id
        or public.is_family_owner_of_user(owner_user_id)
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = source_wallet_id
              and w.user_id = auth.uid()
        )
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = destination_wallet_id
              and w.user_id = auth.uid()
        );
$$;

create or replace function public.can_manage_transaction(
    created_by_user_id uuid,
    source_wallet_id uuid,
    destination_wallet_id uuid,
    owner_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        public.is_family_owner_of_user(owner_user_id)
        or (
            auth.uid() = created_by_user_id
            and public.can_operate_wallet(source_wallet_id)
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
        )
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = source_wallet_id
              and w.user_id = auth.uid()
        )
        or exists (
            select 1
            from public.ledger_wallets w
            where w.id = destination_wallet_id
              and w.user_id = auth.uid()
        );
$$;

drop policy if exists "family_wallet_access_grants_owner_all" on public.family_wallet_access_grants;
create policy "family_wallet_access_grants_owner_all"
on public.family_wallet_access_grants
for all
to authenticated
using (public.is_family_owner(family_id))
with check (public.is_family_owner(family_id));

drop policy if exists "family_wallet_access_grants_grantee_select" on public.family_wallet_access_grants;
create policy "family_wallet_access_grants_grantee_select"
on public.family_wallet_access_grants
for select
to authenticated
using (
    grantee_user_id = auth.uid()
    and revoked_at is null
);

drop policy if exists "wallets_family_member_select" on public.ledger_wallets;
create policy "wallets_family_access_select"
on public.ledger_wallets
for select
to authenticated
using (public.has_family_wallet_access(user_id));

drop policy if exists "credit_card_profiles_family_access_select" on public.credit_card_profiles;
create policy "credit_card_profiles_family_access_select"
on public.credit_card_profiles
for select
to authenticated
using (public.has_family_wallet_access(user_id));

drop policy if exists "categories_family_member_select" on public.transaction_categories;
create policy "categories_family_access_select"
on public.transaction_categories
for select
to authenticated
using (public.has_family_wallet_access(user_id));

drop policy if exists "transactions_family_member_select" on public.ledger_transactions;
create policy "transactions_access_select"
on public.ledger_transactions
for select
to authenticated
using (
    public.can_read_transaction(
        user_id,
        created_by_user_id,
        source_wallet_id,
        destination_wallet_id
    )
);

drop policy if exists "transactions_access_insert" on public.ledger_transactions;
create policy "transactions_access_insert"
on public.ledger_transactions
for insert
to authenticated
with check (
    created_by_user_id = auth.uid()
    and last_modified_by_user_id = auth.uid()
    and source_wallet_id is not null
    and public.can_operate_wallet(source_wallet_id)
    and (
        destination_wallet_id is null
        or public.can_operate_wallet(destination_wallet_id)
    )
    and user_id = public.wallet_owner_user_id(source_wallet_id)
    and public.transaction_category_matches_owner(
        category_id,
        public.wallet_owner_user_id(source_wallet_id)
    )
);

drop policy if exists "transactions_access_update" on public.ledger_transactions;
create policy "transactions_access_update"
on public.ledger_transactions
for update
to authenticated
using (
    public.can_manage_transaction(
        created_by_user_id,
        source_wallet_id,
        destination_wallet_id,
        user_id
    )
)
with check (
    source_wallet_id is not null
    and public.can_manage_transaction(
        created_by_user_id,
        source_wallet_id,
        destination_wallet_id,
        user_id
    )
    and last_modified_by_user_id = auth.uid()
    and user_id = public.wallet_owner_user_id(source_wallet_id)
    and public.transaction_category_matches_owner(
        category_id,
        public.wallet_owner_user_id(source_wallet_id)
    )
);

drop policy if exists "transactions_access_delete" on public.ledger_transactions;
create policy "transactions_access_delete"
on public.ledger_transactions
for delete
to authenticated
using (
    public.can_manage_transaction(
        created_by_user_id,
        source_wallet_id,
        destination_wallet_id,
        user_id
    )
);


-- 20260417010000_fix_family_roster_select.sql

-- Restore roster visibility for all active family members.
-- This keeps data-access permissions separate from roster visibility:
-- members can see who is in the family, but finance access still follows
-- the existing wallet/transaction policies.

create or replace function public.is_family_member(family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.family_memberships
    where public.family_memberships.family_id = $1
      and public.family_memberships.user_id = auth.uid()
      and public.family_memberships.deleted_at is null
  );
$$;

create or replace function public.my_active_family_member_user_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct fm.user_id
  from public.family_memberships fm
  where fm.deleted_at is null
    and fm.family_id in (
      select family_id
      from public.family_memberships
      where user_id = auth.uid()
        and deleted_at is null
    );
$$;

drop policy if exists "family_memberships_self_select" on public.family_memberships;
drop policy if exists "family_memberships_others_select" on public.family_memberships;
drop policy if exists "family_memberships_member_select" on public.family_memberships;
drop policy if exists "family_memberships_family_roster_select" on public.family_memberships;

create policy "family_memberships_family_roster_select"
on public.family_memberships
for select
to authenticated
using (
  deleted_at is null
  and public.is_family_member(family_id)
);

drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_family_members"
on public.user_profiles
for select
to authenticated
using (
  auth.uid() = user_id
  or user_id in (select public.my_active_family_member_user_ids())
);


