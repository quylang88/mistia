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
