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
