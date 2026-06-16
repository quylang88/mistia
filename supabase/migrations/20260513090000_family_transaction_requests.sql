-- Family transaction requests let a family member propose one transaction
-- without granting any long-lived permission on the owner's data.

alter table public.user_profiles
    add column if not exists category_catalog_synced_at timestamptz;

create or replace function public.mark_category_catalog_ready()
returns public.user_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    profile_row public.user_profiles;
begin
    if actor_id is null then
        raise exception 'Not authenticated';
    end if;

    insert into public.user_profiles (
        user_id,
        display_name,
        category_catalog_synced_at
    )
    values (
        actor_id,
        '',
        timezone('utc'::text, now())
    )
    on conflict (user_id)
    do update set
        category_catalog_synced_at = excluded.category_catalog_synced_at,
        updated_at = timezone('utc'::text, now())
    returning * into profile_row;

    return profile_row;
end;
$$;

alter table public.family_notifications
    drop constraint if exists family_notifications_kind_check,
    add constraint family_notifications_kind_check
        check (kind in (
            'permission_request_received',
            'permission_request_approved',
            'permission_request_rejected',
            'permission_revoked',
            'permission_policy_changed',
            'transaction_request_received',
            'transaction_request_approved',
            'transaction_request_rejected',
            'family_activity',
            'access_issue'
        ));

alter table public.family_notifications
    drop constraint if exists family_notifications_resource_type_check,
    add constraint family_notifications_resource_type_check
        check (resource_type is null or resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment'));

create table if not exists public.family_transaction_requests (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    requester_user_id uuid not null references auth.users(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    transaction_payload jsonb not null,
    category_payload jsonb,
    status text not null default 'pending',
    responded_by_user_id uuid references auth.users(id) on delete set null,
    responded_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    sync_version bigint not null default 1,
    constraint family_transaction_requests_status_check
        check (status in ('pending', 'approved', 'rejected', 'canceled'))
);

create index if not exists family_transaction_requests_owner_idx
    on public.family_transaction_requests(owner_user_id, status, created_at desc);

create index if not exists family_transaction_requests_requester_idx
    on public.family_transaction_requests(requester_user_id, created_at desc);

drop trigger if exists family_transaction_requests_set_updated_at on public.family_transaction_requests;
create trigger family_transaction_requests_set_updated_at before update on public.family_transaction_requests
for each row execute function public.set_updated_at();

alter table public.family_transaction_requests enable row level security;

grant select on table public.family_transaction_requests to authenticated;

drop policy if exists "family_transaction_requests_member_select" on public.family_transaction_requests;
create policy "family_transaction_requests_member_select"
on public.family_transaction_requests
for select
to authenticated
using (
    requester_user_id = auth.uid()
    or owner_user_id = auth.uid()
    or public.is_family_owner(family_id)
);

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
              and (
                  c.user_id = owner_user_id
                  or (
                      c.is_system = true
                      and c.system_key is not null
                      and c.deleted_at is null
                  )
              )
        );
$$;

drop policy if exists "categories_family_member_select" on public.transaction_categories;
drop policy if exists "categories_family_access_select" on public.transaction_categories;
create policy "categories_family_access_select"
on public.transaction_categories
for select
to authenticated
using (
    public.has_family_wallet_access(user_id)
    or (
        is_system = true
        and system_key is not null
        and deleted_at is null
    )
);

create or replace function public.resolve_family_transaction_request_category(
    p_owner_user_id uuid,
    p_category jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    requested_category_id uuid;
    requested_parent_id uuid;
    resolved_parent_id uuid;
    resolved_category_id uuid;
    raw_name text;
    raw_kind text;
    raw_icon text;
    raw_color text;
    raw_hierarchy_role text;
    raw_system_key text;
    raw_parent_system_key text;
    is_system_category boolean;
    now_utc timestamptz := timezone('utc'::text, now());
begin
    if p_category is null then
        return null;
    end if;

    requested_category_id := nullif(p_category->>'id', '')::uuid;
    requested_parent_id := nullif(p_category->>'parent_category_id', '')::uuid;
    raw_name := coalesce(nullif(p_category->>'name', ''), 'Category');
    raw_kind := coalesce(nullif(p_category->>'kind_raw_value', ''), 'expense');
    raw_icon := coalesce(nullif(p_category->>'icon_symbol_name', ''), 'tag.fill');
    raw_color := coalesce(nullif(p_category->>'icon_color_hex', ''), '#8E8E93');
    raw_hierarchy_role := coalesce(nullif(p_category->>'hierarchy_role_raw_value', ''), 'child');
    raw_system_key := nullif(p_category->>'system_key', '');
    raw_parent_system_key := nullif(p_category->>'parent_system_key', '');
    is_system_category := coalesce((p_category->>'is_system')::boolean, false);

    if is_system_category and requested_category_id is not null then
        if requested_parent_id is not null then
            select id
            into resolved_parent_id
            from public.transaction_categories
            where id = requested_parent_id
            limit 1;

            if resolved_parent_id is null and raw_parent_system_key is not null then
                insert into public.transaction_categories (
                    id,
                    user_id,
                    name,
                    kind_raw_value,
                    icon_symbol_name,
                    icon_color_hex,
                    is_favorite,
                    parent_category_id,
                    hierarchy_role_raw_value,
                    system_key,
                    is_system,
                    sort_order,
                    is_archived,
                    created_at,
                    updated_at,
                    deleted_at
                )
                values (
                    requested_parent_id,
                    p_owner_user_id,
                    coalesce(nullif(p_category->>'parent_name', ''), 'Category'),
                    raw_kind,
                    'folder.fill',
                    '#8E8E93',
                    false,
                    null,
                    'parent',
                    raw_parent_system_key,
                    true,
                    0,
                    false,
                    now_utc,
                    now_utc,
                    null
                )
                on conflict (id)
                do update set
                    user_id = excluded.user_id,
                    deleted_at = null,
                    updated_at = now_utc,
                    sync_version = public.transaction_categories.sync_version + 1
                returning id into resolved_parent_id;
            end if;
        end if;

        insert into public.transaction_categories (
            id,
            user_id,
            name,
            kind_raw_value,
            icon_symbol_name,
            icon_color_hex,
            is_favorite,
            parent_category_id,
            hierarchy_role_raw_value,
            system_key,
            is_system,
            sort_order,
            is_archived,
            archived_at,
            created_at,
            updated_at,
            deleted_at
        )
        values (
            requested_category_id,
            p_owner_user_id,
            raw_name,
            raw_kind,
            raw_icon,
            raw_color,
            coalesce((p_category->>'is_favorite')::boolean, false),
            resolved_parent_id,
            raw_hierarchy_role,
            raw_system_key,
            true,
            coalesce((p_category->>'sort_order')::integer, 0),
            coalesce((p_category->>'is_archived')::boolean, false),
            null,
            coalesce((p_category->>'created_at')::timestamptz, now_utc),
            now_utc,
            null
        )
        on conflict (id)
        do update set
            user_id = excluded.user_id,
            name = excluded.name,
            kind_raw_value = excluded.kind_raw_value,
            icon_symbol_name = excluded.icon_symbol_name,
            icon_color_hex = excluded.icon_color_hex,
            is_favorite = excluded.is_favorite,
            parent_category_id = excluded.parent_category_id,
            hierarchy_role_raw_value = excluded.hierarchy_role_raw_value,
            system_key = excluded.system_key,
            is_system = true,
            sort_order = excluded.sort_order,
            is_archived = excluded.is_archived,
            archived_at = excluded.archived_at,
            deleted_at = null,
            updated_at = now_utc,
            sync_version = public.transaction_categories.sync_version + 1
        returning id into resolved_category_id;

        return resolved_category_id;
    end if;

    if requested_parent_id is not null then
        select id
        into resolved_parent_id
        from public.transaction_categories
        where id = requested_parent_id
          and user_id = p_owner_user_id
          and deleted_at is null
        limit 1;
    end if;

    if resolved_parent_id is null and raw_parent_system_key is not null then
        select id
        into resolved_parent_id
        from public.transaction_categories
        where system_key = raw_parent_system_key
          and is_system = true
          and deleted_at is null
        limit 1;
    end if;

    if resolved_parent_id is null and nullif(p_category->>'parent_name', '') is not null then
        select id
        into resolved_parent_id
        from public.transaction_categories
        where user_id = p_owner_user_id
          and kind_raw_value = raw_kind
          and hierarchy_role_raw_value = 'parent'
          and lower(btrim(name)) = lower(btrim(p_category->>'parent_name'))
          and deleted_at is null
        order by updated_at desc
        limit 1;
    end if;

    select id
    into resolved_category_id
    from public.transaction_categories
    where user_id = p_owner_user_id
      and kind_raw_value = raw_kind
      and coalesce(parent_category_id, '00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(resolved_parent_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and lower(btrim(name)) = lower(btrim(raw_name))
      and deleted_at is null
      and is_system = false
    order by updated_at desc
    limit 1;

    if resolved_category_id is null then
        insert into public.transaction_categories (
            id,
            user_id,
            name,
            kind_raw_value,
            icon_symbol_name,
            icon_color_hex,
            is_favorite,
            parent_category_id,
            hierarchy_role_raw_value,
            system_key,
            is_system,
            sort_order,
            is_archived,
            archived_at,
            created_at,
            updated_at,
            deleted_at
        )
        values (
            gen_random_uuid(),
            p_owner_user_id,
            raw_name,
            raw_kind,
            raw_icon,
            raw_color,
            coalesce((p_category->>'is_favorite')::boolean, false),
            resolved_parent_id,
            raw_hierarchy_role,
            null,
            false,
            coalesce((p_category->>'sort_order')::integer, 0),
            false,
            null,
            now_utc,
            now_utc,
            null
        )
        returning id into resolved_category_id;
    end if;

    return resolved_category_id;
end;
$$;

create or replace function public.create_family_transaction_request(
    p_family_id uuid,
    p_owner_user_id uuid,
    p_transaction jsonb,
    p_category jsonb,
    p_title text,
    p_body text
)
returns public.family_transaction_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_id uuid := auth.uid();
    source_wallet_id uuid;
    source_wallet_owner_id uuid;
    owner_catalog_ready_at timestamptz;
    request_row public.family_transaction_requests;
begin
    if requester_id is null then
        raise exception 'Not authenticated';
    end if;

    if requester_id = p_owner_user_id then
        raise exception 'Use direct transaction creation for your own wallet';
    end if;

    if not public.active_family_member_exists(p_family_id, requester_id)
       or not public.active_family_member_exists(p_family_id, p_owner_user_id) then
        raise exception 'Both users must be active family members';
    end if;

    select category_catalog_synced_at
    into owner_catalog_ready_at
    from public.user_profiles
    where user_id = p_owner_user_id;

    if owner_catalog_ready_at is null then
        raise exception 'Owner category catalog is not ready';
    end if;

    source_wallet_id := nullif(p_transaction->>'source_wallet_id', '')::uuid;
    if source_wallet_id is null then
        raise exception 'Transaction request requires a source wallet';
    end if;

    select user_id
    into source_wallet_owner_id
    from public.ledger_wallets
    where id = source_wallet_id
      and deleted_at is null
    limit 1;

    if source_wallet_owner_id is null then
        raise exception 'Wallet not found';
    end if;

    if source_wallet_owner_id <> p_owner_user_id then
        raise exception 'Wallet owner mismatch';
    end if;

    if not public.can_operate_wallet(source_wallet_id) then
        raise exception 'You do not have permission to use this wallet';
    end if;

    insert into public.family_transaction_requests (
        family_id,
        requester_user_id,
        owner_user_id,
        transaction_payload,
        category_payload,
        status
    )
    values (
        p_family_id,
        requester_id,
        p_owner_user_id,
        p_transaction,
        p_category,
        'pending'
    )
    returning * into request_row;

    insert into public.family_notifications (
        source_event_key,
        family_id,
        user_id,
        actor_user_id,
        kind,
        resource_type,
        resource_id,
        action_state,
        title,
        body,
        metadata
    )
    values (
        'transaction-request:' || request_row.id::text,
        p_family_id,
        p_owner_user_id,
        requester_id,
        'transaction_request_received',
        'transaction',
        request_row.id,
        'pending',
        coalesce(nullif(p_title, ''), 'Yêu cầu tạo giao dịch'),
        coalesce(nullif(p_body, ''), 'Một thành viên muốn tạo giao dịch trên ví của bạn.'),
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

create or replace function public.respond_family_transaction_request(
    p_request_id uuid,
    p_approve boolean
)
returns public.family_transaction_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    responder_id uuid := auth.uid();
    request_row public.family_transaction_requests;
    transaction_payload jsonb;
    category_payload jsonb;
    source_wallet_id uuid;
    source_wallet_owner_id uuid;
    destination_wallet_id uuid;
    resolved_category_id uuid;
    created_transaction_id uuid;
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
    from public.family_transaction_requests
    where id = p_request_id
    for update;

    if request_row.id is null then
        raise exception 'Transaction request not found';
    end if;

    if request_row.owner_user_id <> responder_id then
        raise exception 'Only the owner can respond to this transaction request';
    end if;

    if request_row.status <> 'pending' then
        return request_row;
    end if;

    transaction_payload := request_row.transaction_payload;
    category_payload := request_row.category_payload;

    if p_approve then
        source_wallet_id := nullif(transaction_payload->>'source_wallet_id', '')::uuid;
        destination_wallet_id := nullif(transaction_payload->>'destination_wallet_id', '')::uuid;

        select user_id
        into source_wallet_owner_id
        from public.ledger_wallets
        where id = source_wallet_id
          and deleted_at is null
        limit 1;

        if source_wallet_owner_id <> request_row.owner_user_id then
            raise exception 'Wallet owner mismatch';
        end if;

        if destination_wallet_id is not null
           and not exists (
                select 1
                from public.ledger_wallets
                where id = destination_wallet_id
                  and user_id = request_row.owner_user_id
                  and deleted_at is null
           ) then
            raise exception 'Destination wallet owner mismatch';
        end if;

        resolved_category_id := public.resolve_family_transaction_request_category(
            request_row.owner_user_id,
            category_payload
        );
        created_transaction_id := coalesce(
            nullif(transaction_payload->>'id', '')::uuid,
            gen_random_uuid()
        );

        insert into public.ledger_transactions (
            id,
            user_id,
            primary_kind_raw_value,
            transfer_subtype_raw_value,
            debt_intent_raw_value,
            entry_status_raw_value,
            title,
            note,
            amount_minor,
            occurred_at,
            source_wallet_id,
            destination_wallet_id,
            category_id,
            created_by_user_id,
            last_modified_by_user_id,
            created_at,
            updated_at,
            deleted_at,
            is_archived,
            archived_at
        )
        values (
            created_transaction_id,
            request_row.owner_user_id,
            coalesce(nullif(transaction_payload->>'primary_kind_raw_value', ''), 'expense'),
            nullif(transaction_payload->>'transfer_subtype_raw_value', ''),
            nullif(transaction_payload->>'debt_intent_raw_value', ''),
            coalesce(nullif(transaction_payload->>'entry_status_raw_value', ''), 'posted'),
            coalesce(transaction_payload->>'title', ''),
            nullif(transaction_payload->>'note', ''),
            (transaction_payload->>'amount_minor')::bigint,
            (transaction_payload->>'occurred_at')::timestamptz,
            source_wallet_id,
            destination_wallet_id,
            resolved_category_id,
            request_row.requester_user_id,
            request_row.requester_user_id,
            coalesce((transaction_payload->>'created_at')::timestamptz, timezone('utc'::text, now())),
            timezone('utc'::text, now()),
            null,
            false,
            null
        );

        update public.family_transaction_requests
        set status = 'approved',
            responded_by_user_id = responder_id,
            responded_at = timezone('utc'::text, now())
        where id = p_request_id
        returning * into request_row;

        result_kind := 'transaction_request_approved';
        result_state := 'approved';
        result_title := 'Giao dịch đã được chấp thuận';
        result_body := 'Giao dịch gia đình bạn đề xuất đã được tạo.';
    else
        update public.family_transaction_requests
        set status = 'rejected',
            responded_by_user_id = responder_id,
            responded_at = timezone('utc'::text, now())
        where id = p_request_id
        returning * into request_row;

        result_kind := 'transaction_request_rejected';
        result_state := 'rejected';
        result_title := 'Giao dịch đã bị từ chối';
        result_body := 'Giao dịch gia đình bạn đề xuất chưa được tạo.';
    end if;

    update public.family_notifications
    set action_state = result_state,
        updated_at = timezone('utc'::text, now())
    where resource_type = 'transaction'
      and resource_id = p_request_id
      and kind = 'transaction_request_received'
      and user_id = responder_id;

    insert into public.family_notifications (
        source_event_key,
        family_id,
        user_id,
        actor_user_id,
        kind,
        resource_type,
        resource_id,
        action_state,
        title,
        body,
        metadata
    )
    values (
        'transaction-result:' || request_row.id::text || ':' || result_state,
        request_row.family_id,
        request_row.requester_user_id,
        responder_id,
        result_kind,
        'transaction',
        request_row.id,
        result_state,
        result_title,
        result_body,
        jsonb_build_object(
            'request_id', request_row.id,
            'transaction_id', created_transaction_id
        )
    )
    on conflict (source_event_key) do nothing;

    return request_row;
end;
$$;

grant execute on function public.mark_category_catalog_ready() to authenticated;
grant execute on function public.create_family_transaction_request(uuid, uuid, jsonb, jsonb, text, text) to authenticated;
grant execute on function public.respond_family_transaction_request(uuid, boolean) to authenticated;
