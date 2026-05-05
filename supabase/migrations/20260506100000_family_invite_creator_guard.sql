create or replace function public.accept_family_invite(
    p_token text
)
returns public.family_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    invite_row public.family_invites;
    family_row public.families;
    existing_same_family public.family_memberships;
    existing_other_family_id uuid;
    membership_row public.family_memberships;
    owner_row record;
    actor_name text;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để tham gia gia đình.';
    end if;

    select *
    into invite_row
    from public.family_invites fi
    where fi.token = trim(p_token)
      and fi.deleted_at is null
    limit 1;

    if invite_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    if invite_row.created_by_user_id = actor_id then
        raise exception 'Link này không khả dụng với tài khoản của bạn. Hãy gửi link cho thành viên cần tham gia.';
    end if;

    select *
    into family_row
    from public.families f
    where f.id = invite_row.family_id
      and f.deleted_at is null
    limit 1;

    if family_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    if invite_row.default_role not in ('member', 'kid') then
        raise exception 'Lời mời owner không còn được hỗ trợ. Hãy yêu cầu chủ sở hữu tạo lời mời thành viên mới.';
    end if;

    if invite_row.revoked_at is not null then
        raise exception 'Lời mời này đã bị thu hồi.';
    end if;

    if invite_row.accepted_at is not null then
        raise exception 'Lời mời này đã được sử dụng.';
    end if;

    if invite_row.expires_at < timezone('utc'::text, now()) then
        raise exception 'Lời mời đã hết hạn. Vui lòng yêu cầu người mời gửi lại link mới.';
    end if;

    select *
    into existing_same_family
    from public.family_memberships fm
    where fm.family_id = invite_row.family_id
      and fm.user_id = actor_id
      and fm.deleted_at is null
    limit 1;

    if existing_same_family.id is not null then
        raise exception 'Bạn đã là thành viên của gia đình này.';
    end if;

    select family_id
    into existing_other_family_id
    from public.family_memberships fm
    where fm.user_id = actor_id
      and fm.family_id <> invite_row.family_id
      and fm.deleted_at is null
    limit 1;

    if existing_other_family_id is not null then
        raise exception 'Tài khoản này hiện đã thuộc một gia đình khác. Vui lòng rời gia đình hiện tại trước khi tham gia gia đình mới.';
    end if;

    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (
        invite_row.family_id,
        actor_id,
        invite_row.default_role,
        invite_row.default_role = 'member',
        invite_row.default_role = 'member',
        false,
        true,
        invite_row.default_role = 'member',
        false,
        false
    )
    returning * into membership_row;

    update public.family_invites fi
    set accepted_at = timezone('utc'::text, now()),
        accepted_by_user_id = actor_id
    where fi.id = invite_row.id;

    select up.display_name
    into actor_name
    from public.user_profiles up
    where up.user_id = actor_id
    limit 1;

    for owner_row in
        select fm.user_id
        from public.family_memberships fm
        where fm.family_id = invite_row.family_id
          and fm.role = 'owner'
          and fm.user_id <> actor_id
          and fm.deleted_at is null
    loop
        insert into public.family_notifications (
            source_event_key,
            family_id,
            user_id,
            actor_user_id,
            kind,
            resource_type,
            action_state,
            title,
            body,
            metadata
        )
        values (
            'family-member-joined:' || invite_row.family_id::text || ':' || actor_id::text || ':' || owner_row.user_id::text,
            invite_row.family_id,
            owner_row.user_id,
            actor_id,
            'family_activity',
            'permission',
            'informational',
            'Thành viên mới đã tham gia',
            coalesce(nullif(actor_name, ''), 'Một thành viên') || ' vừa tham gia gia đình.',
            jsonb_build_object('member_user_id', actor_id)
        )
        on conflict (source_event_key) do nothing;
    end loop;

    return membership_row;
end;
$$;

grant execute on function public.accept_family_invite(text) to authenticated;
