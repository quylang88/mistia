alter table public.recurring_bill_plans
    add column if not exists first_scheduled_month timestamptz;

alter table public.credit_card_profiles
    add column if not exists auto_pay_enabled boolean not null default true;

alter table public.family_permission_grants
    drop constraint if exists family_permission_grants_resource_type_check,
    add constraint family_permission_grants_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer'));

alter table public.family_permission_requests
    drop constraint if exists family_permission_requests_resource_type_check,
    add constraint family_permission_requests_resource_type_check
        check (resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer'));

alter table public.family_notifications
    drop constraint if exists family_notifications_resource_type_check,
    add constraint family_notifications_resource_type_check
        check (resource_type is null or resource_type in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer'));

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

    if p_permission_scope not in ('use', 'edit', 'create', 'view') then
        raise exception 'Unsupported permission scope';
    end if;

    if p_resource_type not in ('wallet', 'category', 'budget', 'goal', 'card', 'debt', 'transaction', 'permission', 'bill', 'due', 'installment', 'family_transfer') then
        raise exception 'Unsupported permission resource type';
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

    if p_resource_type = 'category'
       and p_permission_scope = 'use'
       and (
            not public.user_has_synced_finance_data(requester_id)
            or not public.user_has_synced_finance_data(p_recipient_user_id)
       ) then
        raise exception 'Both users must sync data to cloud before requesting a system category';
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

grant execute on function public.create_family_permission_request(uuid, uuid, text, uuid, text, text, text, text) to authenticated;
