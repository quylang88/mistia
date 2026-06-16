alter table public.family_invites
    add column if not exists declined_at timestamptz,
    add column if not exists declined_by_user_id uuid references auth.users(id) on delete set null;

create index if not exists family_invites_active_pending_idx
    on public.family_invites(family_id, expires_at)
    where accepted_at is null
      and declined_at is null
      and revoked_at is null
      and deleted_at is null;

create or replace function public.create_family_invite_link(
    p_family_id uuid,
    p_default_role text,
    p_expires_at timestamptz
)
returns public.family_invites
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    normalized_role text := coalesce(nullif(p_default_role, ''), 'member');
    family_row public.families;
    active_pending_count integer;
    invite_row public.family_invites;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để tạo lời mời.';
    end if;

    if normalized_role not in ('member', 'kid') then
        raise exception 'Gia đình chỉ có một chủ sở hữu. Hãy mời thành viên rồi nhượng quyền owner sau.';
    end if;

    select f.*
    into family_row
    from public.families f
    join public.family_memberships fm on fm.family_id = f.id
    where f.id = p_family_id
      and f.deleted_at is null
      and f.owner_user_id = actor_id
      and fm.user_id = actor_id
      and fm.role = 'owner'
      and fm.deleted_at is null
    for update of f;

    if family_row.id is null then
        raise exception 'Chỉ chủ sở hữu mới có thể mời thành viên.';
    end if;

    select count(*)
    into active_pending_count
    from public.family_invites fi
    where fi.family_id = p_family_id
      and fi.accepted_at is null
      and fi.declined_at is null
      and fi.revoked_at is null
      and fi.deleted_at is null
      and fi.expires_at >= timezone('utc'::text, now());

    if active_pending_count >= 2 then
        raise exception 'Bạn chỉ có thể có tối đa 2 lời mời đang chờ. Hãy chờ lời mời hết hạn, bị từ chối, được chấp nhận hoặc thu hồi trước khi tạo thêm.';
    end if;

    insert into public.family_invites (
        family_id,
        code,
        token,
        created_by_user_id,
        default_role,
        expires_at
    )
    values (
        p_family_id,
        public.family_invite_legacy_code(),
        public.family_invite_token(),
        actor_id,
        normalized_role,
        p_expires_at
    )
    returning * into invite_row;

    return invite_row;
end;
$$;

create or replace function public.preview_family_invite(
    p_token text
)
returns table (
    invite_id uuid,
    family_id uuid,
    family_name text,
    inviter_user_id uuid,
    inviter_name text,
    role text,
    expires_at timestamptz,
    created_at timestamptz,
    accepted_by_user_id uuid,
    status text,
    already_member_of_family boolean,
    belongs_to_another_family boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    invite_row public.family_invites;
    family_row public.families;
    invited_family_membership_id uuid;
    other_family_membership_id uuid;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để xem lời mời.';
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

    select *
    into family_row
    from public.families f
    where f.id = invite_row.family_id
      and f.deleted_at is null
    limit 1;

    if family_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    select id
    into invited_family_membership_id
    from public.family_memberships fm
    where fm.user_id = actor_id
      and fm.family_id = invite_row.family_id
      and fm.deleted_at is null
    limit 1;

    select id
    into other_family_membership_id
    from public.family_memberships fm
    where fm.user_id = actor_id
      and fm.family_id <> invite_row.family_id
      and fm.deleted_at is null
    limit 1;

    invite_id := invite_row.id;
    family_id := invite_row.family_id;
    family_name := family_row.name;
    inviter_user_id := invite_row.created_by_user_id;
    inviter_name := coalesce(
        (
            select nullif(display_name, '')
            from public.user_profiles up
            where up.user_id = invite_row.created_by_user_id
            limit 1
        ),
        'Mistia'
    );
    role := invite_row.default_role;
    expires_at := invite_row.expires_at;
    created_at := invite_row.created_at;
    accepted_by_user_id := invite_row.accepted_by_user_id;
    already_member_of_family := invited_family_membership_id is not null;
    belongs_to_another_family := other_family_membership_id is not null;

    if invite_row.accepted_at is not null or already_member_of_family then
        status := 'accepted';
    elsif invite_row.declined_at is not null then
        status := 'declined';
    elsif invite_row.revoked_at is not null then
        status := 'revoked';
    elsif invite_row.expires_at < timezone('utc'::text, now()) then
        status := 'expired';
    else
        status := 'pending';
    end if;

    return next;
end;
$$;

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
    for update;

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

    if invite_row.declined_at is not null then
        raise exception 'Lời mời này đã bị từ chối.';
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

create or replace function public.decline_family_invite(
    p_token text
)
returns public.family_invites
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    invite_row public.family_invites;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để từ chối lời mời.';
    end if;

    select *
    into invite_row
    from public.family_invites fi
    where fi.token = trim(p_token)
      and fi.deleted_at is null
    for update;

    if invite_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    if invite_row.created_by_user_id = actor_id then
        raise exception 'Link này không khả dụng với tài khoản của bạn. Hãy gửi link cho thành viên cần tham gia.';
    end if;

    if invite_row.accepted_at is not null then
        raise exception 'Lời mời này đã được sử dụng.';
    end if;

    if invite_row.revoked_at is not null then
        raise exception 'Lời mời này đã bị thu hồi.';
    end if;

    if invite_row.expires_at < timezone('utc'::text, now()) then
        raise exception 'Lời mời đã hết hạn. Vui lòng yêu cầu người mời gửi lại link mới.';
    end if;

    update public.family_invites fi
    set declined_at = coalesce(fi.declined_at, timezone('utc'::text, now())),
        declined_by_user_id = coalesce(fi.declined_by_user_id, actor_id)
    where fi.id = invite_row.id
    returning * into invite_row;

    return invite_row;
end;
$$;

grant execute on function public.create_family_invite_link(uuid, text, timestamptz) to authenticated;
grant execute on function public.preview_family_invite(text) to authenticated;
grant execute on function public.accept_family_invite(text) to authenticated;
grant execute on function public.decline_family_invite(text) to authenticated;
