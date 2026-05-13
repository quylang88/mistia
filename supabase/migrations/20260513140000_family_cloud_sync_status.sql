-- Category-use requests only require both family users to have synced any
-- finance data to cloud at least once; the old category-catalog flag is no
-- longer a source of truth.

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
        or exists (select 1 from public.ledger_transactions where user_id = p_user_id limit 1)
        or exists (select 1 from public.budget_plans where user_id = p_user_id limit 1)
        or exists (select 1 from public.savings_goals where user_id = p_user_id limit 1)
        or exists (select 1 from public.recurring_bill_plans where user_id = p_user_id limit 1)
        or exists (select 1 from public.installment_plans where user_id = p_user_id limit 1)
        or exists (select 1 from public.due_occurrence_records where user_id = p_user_id limit 1);
$$;

revoke all on function public.user_has_synced_finance_data(uuid) from public;

create or replace function public.family_cloud_sync_status(
    p_family_id uuid
)
returns table (
    user_id uuid,
    has_synced_cloud_data boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
begin
    if actor_id is null then
        raise exception 'Not authenticated';
    end if;

    if not public.active_family_member_exists(p_family_id, actor_id) then
        raise exception 'You are not a member of this family';
    end if;

    return query
    select
        fm.user_id,
        public.user_has_synced_finance_data(fm.user_id) as has_synced_cloud_data
    from public.family_memberships fm
    join public.families f on f.id = fm.family_id
    where fm.family_id = p_family_id
      and fm.deleted_at is null
      and f.deleted_at is null
    order by fm.created_at asc;
end;
$$;

grant execute on function public.family_cloud_sync_status(uuid) to authenticated;

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

drop function if exists public.mark_category_catalog_ready();

alter table public.user_profiles
    drop column if exists category_catalog_synced_at;
