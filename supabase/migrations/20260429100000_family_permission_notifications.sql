-- Family permission request + in-app notification center foundation.
-- This phase is sync-driven only: no push notifications or realtime channel.

create table if not exists public.family_permission_requests (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    requester_user_id uuid not null references auth.users(id) on delete cascade,
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    resource_type text not null,
    resource_id uuid not null,
    permission_scope text not null,
    status text not null default 'pending',
    message text,
    responded_by_user_id uuid references auth.users(id) on delete set null,
    responded_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    constraint family_permission_requests_resource_type_check
        check (resource_type in ('wallet', 'category', 'goal', 'card', 'debt', 'transaction', 'permission')),
    constraint family_permission_requests_scope_check
        check (permission_scope in ('use', 'edit', 'view')),
    constraint family_permission_requests_status_check
        check (status in ('pending', 'approved', 'rejected', 'canceled'))
);

create unique index if not exists family_permission_requests_pending_unique
    on public.family_permission_requests(family_id, requester_user_id, recipient_user_id, resource_type, resource_id, permission_scope)
    where status = 'pending';

create index if not exists family_permission_requests_recipient_idx
    on public.family_permission_requests(recipient_user_id, status, created_at desc);

create index if not exists family_permission_requests_requester_idx
    on public.family_permission_requests(requester_user_id, created_at desc);

drop trigger if exists family_permission_requests_set_updated_at on public.family_permission_requests;
create trigger family_permission_requests_set_updated_at before update on public.family_permission_requests
for each row execute function public.set_updated_at();

alter table public.family_permission_requests enable row level security;

create table if not exists public.family_notifications (
    id uuid primary key default gen_random_uuid(),
    source_event_key text not null unique,
    family_id uuid not null references public.families(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    actor_user_id uuid references auth.users(id) on delete set null,
    kind text not null,
    resource_type text,
    resource_id uuid,
    permission_scope text,
    permission_request_id uuid references public.family_permission_requests(id) on delete set null,
    action_state text not null default 'informational',
    title text not null,
    body text not null,
    metadata jsonb not null default '{}'::jsonb,
    read_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    sync_version bigint not null default 1,
    constraint family_notifications_kind_check
        check (kind in (
            'permission_request_received',
            'permission_request_approved',
            'permission_request_rejected',
            'permission_revoked',
            'permission_policy_changed',
            'family_activity',
            'access_issue'
        )),
    constraint family_notifications_resource_type_check
        check (resource_type is null or resource_type in ('wallet', 'category', 'goal', 'card', 'debt', 'transaction', 'permission')),
    constraint family_notifications_scope_check
        check (permission_scope is null or permission_scope in ('use', 'edit', 'view')),
    constraint family_notifications_action_state_check
        check (action_state in ('informational', 'pending', 'approved', 'rejected', 'revoked', 'canceled', 'resolved'))
);

create index if not exists family_notifications_user_created_idx
    on public.family_notifications(user_id, created_at desc);

create index if not exists family_notifications_unread_idx
    on public.family_notifications(user_id, read_at)
    where read_at is null;

drop trigger if exists family_notifications_set_updated_at on public.family_notifications;
create trigger family_notifications_set_updated_at before update on public.family_notifications
for each row execute function public.set_updated_at();

alter table public.family_notifications enable row level security;

grant select on table public.family_permission_requests to authenticated;
grant select on table public.family_notifications to authenticated;
grant update(read_at) on table public.family_notifications to authenticated;

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
    case p_resource_type
        when 'wallet' then
            select user_id into owner_id from public.ledger_wallets where id = p_resource_id limit 1;
        when 'category' then
            select user_id into owner_id from public.transaction_categories where id = p_resource_id limit 1;
        when 'goal' then
            select user_id into owner_id from public.savings_goals where id = p_resource_id limit 1;
        when 'card' then
            select user_id into owner_id from public.credit_card_profiles where id = p_resource_id limit 1;
        when 'transaction' then
            select user_id into owner_id from public.ledger_transactions where id = p_resource_id limit 1;
        else
            owner_id := null;
    end case;

    return owner_id;
end;
$$;

create or replace function public.active_family_member_exists(
    p_family_id uuid,
    p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.family_memberships fm
        join public.families f on f.id = fm.family_id
        where fm.family_id = p_family_id
          and fm.user_id = p_user_id
          and fm.deleted_at is null
          and f.deleted_at is null
    );
$$;

create or replace function public.shared_active_family_id(
    p_first_user_id uuid,
    p_second_user_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select fm1.family_id
    from public.family_memberships fm1
    join public.family_memberships fm2
      on fm2.family_id = fm1.family_id
    join public.families f
      on f.id = fm1.family_id
    where fm1.user_id = p_first_user_id
      and fm2.user_id = p_second_user_id
      and fm1.deleted_at is null
      and fm2.deleted_at is null
      and f.deleted_at is null
    order by fm1.created_at asc
    limit 1;
$$;

create policy "family_permission_requests_participant_select"
on public.family_permission_requests
for select
to authenticated
using (
    requester_user_id = auth.uid()
    or recipient_user_id = auth.uid()
);

create policy "family_notifications_recipient_select"
on public.family_notifications
for select
to authenticated
using (user_id = auth.uid());

create policy "family_notifications_recipient_update"
on public.family_notifications
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

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

    if not public.active_family_member_exists(p_family_id, requester_id)
       or not public.active_family_member_exists(p_family_id, p_recipient_user_id) then
        raise exception 'Both users must be active family members';
    end if;

    owner_id := public.family_resource_owner_user_id(p_resource_type, p_resource_id);
    if owner_id is not null and owner_id <> p_recipient_user_id then
        raise exception 'Recipient does not own this resource';
    end if;

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
    on conflict (family_id, requester_user_id, recipient_user_id, resource_type, resource_id, permission_scope)
        where status = 'pending'
    do update set
        updated_at = timezone('utc'::text, now()),
        message = excluded.message
    returning * into request_row;

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

        if request_row.resource_type = 'wallet'
           and request_row.permission_scope in ('use', 'edit')
           and not exists (
               select 1
               from public.family_wallet_access_grants g
               where g.family_id = request_row.family_id
                 and g.grantee_user_id = request_row.requester_user_id
                 and g.target_user_id = request_row.recipient_user_id
                 and g.revoked_at is null
           ) then
            insert into public.family_wallet_access_grants (
                family_id,
                grantee_user_id,
                target_user_id,
                granted_by_user_id
            )
            values (
                request_row.family_id,
                request_row.requester_user_id,
                request_row.recipient_user_id,
                responder_id
            );
        end if;

        result_kind := 'permission_request_approved';
        result_state := 'approved';
        result_title := 'Yêu cầu đã được chấp thuận';
        result_body := 'Bạn đã được cấp quyền thao tác trên dữ liệu gia đình.';
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

create or replace function public.mark_family_notifications_read(
    p_notification_ids uuid[]
)
returns void
language sql
security definer
set search_path = public
as $$
    update public.family_notifications
    set read_at = coalesce(read_at, timezone('utc'::text, now())),
        updated_at = timezone('utc'::text, now())
    where user_id = auth.uid()
      and id = any(p_notification_ids);
$$;

create or replace function public.create_family_activity_notification(
    p_recipient_user_id uuid,
    p_resource_type text,
    p_resource_id uuid,
    p_source_event_key text,
    p_title text,
    p_body text,
    p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    shared_family_id uuid;
    notification_id uuid;
begin
    if actor_id is null then
        raise exception 'Not authenticated';
    end if;

    if actor_id = p_recipient_user_id then
        return null;
    end if;

    shared_family_id := public.shared_active_family_id(actor_id, p_recipient_user_id);
    if shared_family_id is null then
        raise exception 'Users do not share an active family';
    end if;

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
        p_source_event_key,
        shared_family_id,
        p_recipient_user_id,
        actor_id,
        'family_activity',
        p_resource_type,
        p_resource_id,
        'informational',
        coalesce(nullif(p_title, ''), 'Hoạt động gia đình'),
        coalesce(nullif(p_body, ''), 'Một thành viên vừa thao tác trên dữ liệu của bạn.'),
        coalesce(p_metadata, '{}'::jsonb)
    )
    on conflict (source_event_key)
    do update set id = family_notifications.id
    returning id into notification_id;

    return notification_id;
end;
$$;

grant execute on function public.create_family_permission_request(uuid, uuid, text, uuid, text, text, text, text) to authenticated;
grant execute on function public.respond_family_permission_request(uuid, boolean) to authenticated;
grant execute on function public.mark_family_notifications_read(uuid[]) to authenticated;
grant execute on function public.create_family_activity_notification(uuid, text, uuid, text, text, text, jsonb) to authenticated;
