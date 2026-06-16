-- Granular family permissions.
-- View permission remains membership/policy based. Use, edit, and create are
-- explicit grants so local reminders stay user-local and family operations are
-- auditable through family_notifications.

create table if not exists public.family_permission_grants (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    grantee_user_id uuid not null references auth.users(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    resource_type text not null,
    resource_id uuid,
    permission_scope text not null,
    granted_by_user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    revoked_at timestamptz,
    constraint family_permission_grants_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment')),
    constraint family_permission_grants_scope_check
        check (permission_scope in ('use', 'edit', 'create', 'view'))
);

create unique index if not exists family_permission_grants_active_unique
    on public.family_permission_grants(
        family_id,
        grantee_user_id,
        owner_user_id,
        resource_type,
        coalesce(resource_id, '00000000-0000-0000-0000-000000000000'::uuid),
        permission_scope
    )
    where revoked_at is null;

create index if not exists family_permission_grants_lookup_idx
    on public.family_permission_grants(grantee_user_id, owner_user_id, resource_type, permission_scope, resource_id)
    where revoked_at is null;

drop trigger if exists family_permission_grants_set_updated_at on public.family_permission_grants;
create trigger family_permission_grants_set_updated_at before update on public.family_permission_grants
for each row execute function public.set_updated_at();

alter table public.family_permission_grants enable row level security;

grant select on table public.family_permission_grants to authenticated;

drop policy if exists "family_permission_grants_member_select" on public.family_permission_grants;
create policy "family_permission_grants_member_select"
on public.family_permission_grants
for select
to authenticated
using (
    public.active_family_member_exists(family_id, auth.uid())
    and (
        grantee_user_id = auth.uid()
        or owner_user_id = auth.uid()
        or public.is_family_owner(family_id)
    )
);

-- Backfill old member-wide wallet grants into per-wallet use grants.
insert into public.family_permission_grants (
    family_id,
    grantee_user_id,
    owner_user_id,
    resource_type,
    resource_id,
    permission_scope,
    granted_by_user_id,
    created_at,
    updated_at,
    revoked_at
)
select
    g.family_id,
    g.grantee_user_id,
    g.target_user_id,
    'wallet',
    w.id,
    'use',
    g.granted_by_user_id,
    g.created_at,
    g.updated_at,
    g.revoked_at
from public.family_wallet_access_grants g
join public.ledger_wallets w
  on w.user_id = g.target_user_id
where w.deleted_at is null
on conflict do nothing;

alter table public.family_permission_requests
    alter column resource_id drop not null;

drop index if exists family_permission_requests_pending_unique;
create unique index family_permission_requests_pending_unique
    on public.family_permission_requests(
        family_id,
        requester_user_id,
        recipient_user_id,
        resource_type,
        coalesce(resource_id, '00000000-0000-0000-0000-000000000000'::uuid),
        permission_scope
    )
    where status = 'pending';

alter table public.family_permission_requests
    drop constraint if exists family_permission_requests_resource_type_check,
    add constraint family_permission_requests_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment'));

alter table public.family_permission_requests
    drop constraint if exists family_permission_requests_scope_check,
    add constraint family_permission_requests_scope_check
        check (permission_scope in ('use', 'edit', 'create', 'view'));

alter table public.family_notifications
    drop constraint if exists family_notifications_resource_type_check,
    add constraint family_notifications_resource_type_check
        check (resource_type is null or resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment'));

alter table public.family_notifications
    drop constraint if exists family_notifications_scope_check,
    add constraint family_notifications_scope_check
        check (permission_scope is null or permission_scope in ('use', 'edit', 'create', 'view'));

create or replace function public.family_resource_owner_user_id(
    p_resource_type text,
    p_resource_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    owner_id uuid;
begin
    if p_resource_id is null then
        return null;
    end if;

    case p_resource_type
        when 'wallet' then
            select user_id into owner_id from public.ledger_wallets where id = p_resource_id limit 1;
        when 'category' then
            select user_id into owner_id from public.transaction_categories where id = p_resource_id limit 1;
        when 'budget' then
            select user_id into owner_id from public.budget_plans where id = p_resource_id limit 1;
        when 'goal' then
            select user_id into owner_id from public.savings_goals where id = p_resource_id limit 1;
        when 'card' then
            select user_id into owner_id from public.credit_card_profiles where id = p_resource_id limit 1;
        when 'transaction' then
            select user_id into owner_id from public.ledger_transactions where id = p_resource_id limit 1;
        when 'bill' then
            select user_id into owner_id from public.recurring_bill_plans where id = p_resource_id limit 1;
        when 'due' then
            select user_id into owner_id from public.due_occurrence_records where id = p_resource_id limit 1;
        when 'installment' then
            select user_id into owner_id from public.installment_plans where id = p_resource_id limit 1;
        else
            owner_id := null;
    end case;

    return owner_id;
end;
$$;

create or replace function public.has_family_permission_grant(
    p_owner_user_id uuid,
    p_resource_type text,
    p_resource_id uuid,
    p_permission_scope text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = p_owner_user_id
        or exists (
            select 1
            from public.family_permission_grants g
            join public.families f
              on f.id = g.family_id
            join public.family_memberships grantee_membership
              on grantee_membership.family_id = g.family_id
             and grantee_membership.user_id = g.grantee_user_id
            join public.family_memberships owner_membership
              on owner_membership.family_id = g.family_id
             and owner_membership.user_id = g.owner_user_id
            where g.grantee_user_id = auth.uid()
              and g.owner_user_id = p_owner_user_id
              and g.resource_type = p_resource_type
              and g.resource_id is not distinct from p_resource_id
              and g.permission_scope = p_permission_scope
              and g.revoked_at is null
              and f.deleted_at is null
              and grantee_membership.deleted_at is null
              and owner_membership.deleted_at is null
        );
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
          and public.has_family_permission_grant(w.user_id, 'wallet', w.id, 'use')
    );
$$;

create or replace function public.has_family_wallet_operation_access(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = target_user_id
        or exists (
            select 1
            from public.family_permission_grants g
            where g.grantee_user_id = auth.uid()
              and g.owner_user_id = target_user_id
              and g.resource_type = 'wallet'
              and g.permission_scope = 'use'
              and g.revoked_at is null
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
        auth.uid() = owner_user_id
        or (
            public.has_family_permission_grant(owner_user_id, 'transaction', null, 'edit')
            and public.can_operate_wallet(source_wallet_id)
            and (
                destination_wallet_id is null
                or public.can_operate_wallet(destination_wallet_id)
            )
        );
$$;

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
    and public.has_family_permission_grant(user_id, 'transaction', null, 'create')
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

drop policy if exists "wallets_granular_insert" on public.ledger_wallets;
create policy "wallets_granular_insert"
on public.ledger_wallets
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'wallet', null, 'create'));

drop policy if exists "wallets_granular_update" on public.ledger_wallets;
create policy "wallets_granular_update"
on public.ledger_wallets
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'wallet', id, 'edit'))
with check (public.has_family_permission_grant(user_id, 'wallet', id, 'edit'));

drop policy if exists "wallets_granular_delete" on public.ledger_wallets;
create policy "wallets_granular_delete"
on public.ledger_wallets
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'wallet', id, 'edit'));

drop policy if exists "credit_cards_granular_insert" on public.credit_card_profiles;
create policy "credit_cards_granular_insert"
on public.credit_card_profiles
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'wallet', null, 'create'));

drop policy if exists "credit_cards_granular_update" on public.credit_card_profiles;
create policy "credit_cards_granular_update"
on public.credit_card_profiles
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'wallet', wallet_id, 'edit'))
with check (public.has_family_permission_grant(user_id, 'wallet', wallet_id, 'edit'));

drop policy if exists "credit_cards_granular_delete" on public.credit_card_profiles;
create policy "credit_cards_granular_delete"
on public.credit_card_profiles
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'wallet', wallet_id, 'edit'));

drop policy if exists "categories_granular_insert" on public.transaction_categories;
create policy "categories_granular_insert"
on public.transaction_categories
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'category', null, 'create'));

drop policy if exists "categories_granular_update" on public.transaction_categories;
create policy "categories_granular_update"
on public.transaction_categories
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'category', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'category', null, 'edit'));

drop policy if exists "categories_granular_delete" on public.transaction_categories;
create policy "categories_granular_delete"
on public.transaction_categories
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'category', null, 'edit'));

drop policy if exists "budget_plans_granular_insert" on public.budget_plans;
create policy "budget_plans_granular_insert"
on public.budget_plans
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'budget', null, 'create'));

drop policy if exists "budget_plans_granular_update" on public.budget_plans;
create policy "budget_plans_granular_update"
on public.budget_plans
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'budget', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'budget', null, 'edit'));

drop policy if exists "budget_plans_granular_delete" on public.budget_plans;
create policy "budget_plans_granular_delete"
on public.budget_plans
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'budget', null, 'edit'));

drop policy if exists "savings_goals_granular_insert" on public.savings_goals;
create policy "savings_goals_granular_insert"
on public.savings_goals
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'goal', null, 'create'));

drop policy if exists "savings_goals_granular_update" on public.savings_goals;
create policy "savings_goals_granular_update"
on public.savings_goals
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'goal', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'goal', null, 'edit'));

drop policy if exists "savings_goals_granular_delete" on public.savings_goals;
create policy "savings_goals_granular_delete"
on public.savings_goals
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'goal', null, 'edit'));

drop policy if exists "recurring_bill_plans_granular_insert" on public.recurring_bill_plans;
create policy "recurring_bill_plans_granular_insert"
on public.recurring_bill_plans
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'due', null, 'create'));

drop policy if exists "recurring_bill_plans_granular_update" on public.recurring_bill_plans;
create policy "recurring_bill_plans_granular_update"
on public.recurring_bill_plans
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'due', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

drop policy if exists "recurring_bill_plans_granular_delete" on public.recurring_bill_plans;
create policy "recurring_bill_plans_granular_delete"
on public.recurring_bill_plans
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

drop policy if exists "installment_plans_granular_insert" on public.installment_plans;
create policy "installment_plans_granular_insert"
on public.installment_plans
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'due', null, 'create'));

drop policy if exists "installment_plans_granular_update" on public.installment_plans;
create policy "installment_plans_granular_update"
on public.installment_plans
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'due', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

drop policy if exists "installment_plans_granular_delete" on public.installment_plans;
create policy "installment_plans_granular_delete"
on public.installment_plans
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

drop policy if exists "due_occurrence_records_granular_insert" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_insert"
on public.due_occurrence_records
for insert
to authenticated
with check (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

drop policy if exists "due_occurrence_records_granular_update" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_update"
on public.due_occurrence_records
for update
to authenticated
using (public.has_family_permission_grant(user_id, 'due', null, 'edit'))
with check (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

drop policy if exists "due_occurrence_records_granular_delete" on public.due_occurrence_records;
create policy "due_occurrence_records_granular_delete"
on public.due_occurrence_records
for delete
to authenticated
using (public.has_family_permission_grant(user_id, 'due', null, 'edit'));

create or replace function public.create_family_permission_request(
    p_family_id uuid,
    p_recipient_user_id uuid,
    p_resource_type text,
    p_resource_id uuid,
    p_permission_scope text,
    p_title text,
    p_body text,
    p_message text default null
)
returns public.family_permission_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_id uuid := auth.uid();
    owner_id uuid;
    request_row public.family_permission_requests;
begin
    if requester_id is null then
        raise exception 'Not authenticated';
    end if;

    if requester_id = p_recipient_user_id then
        raise exception 'Cannot request permission from yourself';
    end if;

    if p_resource_type = 'wallet'
       and p_permission_scope in ('use', 'edit')
       and p_resource_id is null then
        raise exception 'Wallet use/edit requests require a wallet';
    end if;

    if not public.active_family_member_exists(p_family_id, requester_id)
       or not public.active_family_member_exists(p_family_id, p_recipient_user_id) then
        raise exception 'Both users must be active family members';
    end if;

    owner_id := public.family_resource_owner_user_id(p_resource_type, p_resource_id);
    if owner_id is not null and owner_id <> p_recipient_user_id then
        raise exception 'Recipient does not own this resource';
    end if;

    select *
    into request_row
    from public.family_permission_requests fpr
    where fpr.family_id = p_family_id
      and fpr.requester_user_id = requester_id
      and fpr.recipient_user_id = p_recipient_user_id
      and fpr.resource_type = p_resource_type
      and fpr.resource_id is not distinct from p_resource_id
      and fpr.permission_scope = p_permission_scope
      and fpr.status = 'pending'
    for update;

    if request_row.id is null then
        insert into public.family_permission_requests (
            family_id,
            requester_user_id,
            recipient_user_id,
            resource_type,
            resource_id,
            permission_scope,
            message
        )
        values (
            p_family_id,
            requester_id,
            p_recipient_user_id,
            p_resource_type,
            p_resource_id,
            p_permission_scope,
            p_message
        )
        returning * into request_row;
    else
        update public.family_permission_requests
        set updated_at = timezone('utc'::text, now()),
            message = p_message
        where id = request_row.id
        returning * into request_row;
    end if;

    insert into public.family_notifications (
        source_event_key,
        family_id,
        user_id,
        actor_user_id,
        kind,
        resource_type,
        resource_id,
        permission_scope,
        permission_request_id,
        action_state,
        title,
        body,
        metadata
    )
    values (
        'permission-request:' || request_row.id::text,
        p_family_id,
        p_recipient_user_id,
        requester_id,
        'permission_request_received',
        p_resource_type,
        p_resource_id,
        p_permission_scope,
        request_row.id,
        'pending',
        coalesce(nullif(p_title, ''), 'Yêu cầu quyền mới'),
        coalesce(nullif(p_body, ''), 'Một thành viên đang xin quyền trên dữ liệu của bạn.'),
        jsonb_build_object('request_id', request_row.id)
    )
    on conflict (source_event_key)
    do update set
        updated_at = timezone('utc'::text, now()),
        action_state = 'pending',
        read_at = null;

    return request_row;
end;
$$;

create or replace function public.respond_family_permission_request(
    p_request_id uuid,
    p_approve boolean
)
returns public.family_permission_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    responder_id uuid := auth.uid();
    request_row public.family_permission_requests;
    grant_row public.family_permission_grants;
    result_kind text;
    result_state text;
    result_title text;
    result_body text;
begin
    if responder_id is null then
        raise exception 'Not authenticated';
    end if;

    select *
    into request_row
    from public.family_permission_requests
    where id = p_request_id
    for update;

    if request_row.id is null then
        raise exception 'Permission request not found';
    end if;

    if request_row.recipient_user_id <> responder_id then
        raise exception 'Only the recipient can respond to this request';
    end if;

    if request_row.status <> 'pending' then
        return request_row;
    end if;

    if p_approve then
        update public.family_permission_requests
        set status = 'approved',
            responded_by_user_id = responder_id,
            responded_at = timezone('utc'::text, now())
        where id = p_request_id
        returning * into request_row;

        select *
        into grant_row
        from public.family_permission_grants g
        where g.family_id = request_row.family_id
          and g.grantee_user_id = request_row.requester_user_id
          and g.owner_user_id = request_row.recipient_user_id
          and g.resource_type = request_row.resource_type
          and g.resource_id is not distinct from request_row.resource_id
          and g.permission_scope = request_row.permission_scope
          and g.revoked_at is null
        for update;

        if grant_row.id is null then
            insert into public.family_permission_grants (
                family_id,
                grantee_user_id,
                owner_user_id,
                resource_type,
                resource_id,
                permission_scope,
                granted_by_user_id
            )
            values (
                request_row.family_id,
                request_row.requester_user_id,
                request_row.recipient_user_id,
                request_row.resource_type,
                request_row.resource_id,
                request_row.permission_scope,
                responder_id
            )
            returning * into grant_row;
        else
            update public.family_permission_grants
            set granted_by_user_id = responder_id,
                updated_at = timezone('utc'::text, now())
            where id = grant_row.id
            returning * into grant_row;
        end if;

        result_kind := 'permission_request_approved';
        result_state := 'approved';
        result_title := 'Yêu cầu đã được chấp thuận';
        result_body := 'Bạn đã được cấp quyền trên dữ liệu gia đình.';
    else
        update public.family_permission_requests
        set status = 'rejected',
            responded_by_user_id = responder_id,
            responded_at = timezone('utc'::text, now())
        where id = p_request_id
        returning * into request_row;

        result_kind := 'permission_request_rejected';
        result_state := 'rejected';
        result_title := 'Yêu cầu đã bị từ chối';
        result_body := 'Yêu cầu quyền của bạn chưa được chấp thuận.';
    end if;

    update public.family_notifications
    set action_state = result_state,
        updated_at = timezone('utc'::text, now())
    where permission_request_id = p_request_id
      and user_id = responder_id;

    insert into public.family_notifications (
        source_event_key,
        family_id,
        user_id,
        actor_user_id,
        kind,
        resource_type,
        resource_id,
        permission_scope,
        permission_request_id,
        action_state,
        title,
        body,
        metadata
    )
    values (
        'permission-result:' || request_row.id::text || ':' || result_state,
        request_row.family_id,
        request_row.requester_user_id,
        responder_id,
        result_kind,
        request_row.resource_type,
        request_row.resource_id,
        request_row.permission_scope,
        request_row.id,
        result_state,
        result_title,
        result_body,
        jsonb_build_object('request_id', request_row.id)
    )
    on conflict (source_event_key) do nothing;

    return request_row;
end;
$$;

create or replace function public.set_family_permission_grant(
    p_family_id uuid,
    p_grantee_user_id uuid,
    p_owner_user_id uuid,
    p_resource_type text,
    p_resource_id uuid,
    p_permission_scope text,
    p_is_granted boolean
)
returns public.family_permission_grants
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    owner_id uuid;
    grant_row public.family_permission_grants;
    actor_name text;
    scope_label text;
    action_title text;
    action_body text;
begin
    if actor_id is null then
        raise exception 'Not authenticated';
    end if;

    if p_grantee_user_id = p_owner_user_id then
        raise exception 'Cannot grant permission to the owner';
    end if;

    if not public.active_family_member_exists(p_family_id, p_grantee_user_id)
       or not public.active_family_member_exists(p_family_id, p_owner_user_id)
       or not public.active_family_member_exists(p_family_id, actor_id) then
        raise exception 'All users must be active family members';
    end if;

    if actor_id <> p_owner_user_id and not public.is_family_owner(p_family_id) then
        raise exception 'Only the owner of this data can change this permission';
    end if;

    if p_resource_type = 'wallet'
       and p_permission_scope in ('use', 'edit')
       and p_resource_id is null then
        raise exception 'Wallet use/edit grants require a wallet';
    end if;

    owner_id := public.family_resource_owner_user_id(p_resource_type, p_resource_id);
    if owner_id is not null and owner_id <> p_owner_user_id then
        raise exception 'Resource owner mismatch';
    end if;

    if p_is_granted then
        select *
        into grant_row
        from public.family_permission_grants g
        where g.family_id = p_family_id
          and g.grantee_user_id = p_grantee_user_id
          and g.owner_user_id = p_owner_user_id
          and g.resource_type = p_resource_type
          and g.resource_id is not distinct from p_resource_id
          and g.permission_scope = p_permission_scope
          and g.revoked_at is null
        for update;

        if grant_row.id is null then
            insert into public.family_permission_grants (
                family_id,
                grantee_user_id,
                owner_user_id,
                resource_type,
                resource_id,
                permission_scope,
                granted_by_user_id
            )
            values (
                p_family_id,
                p_grantee_user_id,
                p_owner_user_id,
                p_resource_type,
                p_resource_id,
                p_permission_scope,
                actor_id
            )
            returning * into grant_row;
        else
            update public.family_permission_grants
            set granted_by_user_id = actor_id,
                updated_at = timezone('utc'::text, now())
            where id = grant_row.id
            returning * into grant_row;
        end if;
    else
        select *
        into grant_row
        from public.family_permission_grants g
        where g.family_id = p_family_id
          and g.grantee_user_id = p_grantee_user_id
          and g.owner_user_id = p_owner_user_id
          and g.resource_type = p_resource_type
          and g.resource_id is not distinct from p_resource_id
          and g.permission_scope = p_permission_scope
          and g.revoked_at is null
        for update;

        if grant_row.id is null then
            raise exception 'Permission grant not found';
        end if;

        update public.family_permission_grants
        set revoked_at = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        where id = grant_row.id
        returning * into grant_row;
    end if;

    select up.display_name
    into actor_name
    from public.user_profiles up
    where up.user_id = actor_id
    limit 1;

    scope_label := case p_permission_scope
        when 'use' then 'sử dụng'
        when 'edit' then 'chỉnh sửa'
        when 'create' then 'thêm mới'
        else 'truy cập'
    end;

    action_title := case when p_is_granted then 'Quyền đã được chia sẻ' else 'Quyền đã được thu hồi' end;
    action_body := coalesce(nullif(actor_name, ''), 'Một thành viên')
        || case when p_is_granted then ' đã chia sẻ quyền ' else ' đã thu hồi quyền ' end
        || scope_label || ' với bạn.';

    insert into public.family_notifications (
        source_event_key,
        family_id,
        user_id,
        actor_user_id,
        kind,
        resource_type,
        resource_id,
        permission_scope,
        action_state,
        title,
        body,
        metadata
    )
    values (
        'permission-grant:' || grant_row.id::text || ':' || case when p_is_granted then 'shared' else 'revoked' end || ':' || extract(epoch from grant_row.updated_at)::bigint::text,
        p_family_id,
        p_grantee_user_id,
        actor_id,
        case when p_is_granted then 'permission_policy_changed' else 'permission_revoked' end,
        p_resource_type,
        p_resource_id,
        p_permission_scope,
        case when p_is_granted then 'informational' else 'revoked' end,
        action_title,
        action_body,
        jsonb_build_object('grant_id', grant_row.id)
    )
    on conflict (source_event_key) do nothing;

    return grant_row;
end;
$$;

grant execute on function public.set_family_permission_grant(uuid, uuid, uuid, text, uuid, text, boolean) to authenticated;
