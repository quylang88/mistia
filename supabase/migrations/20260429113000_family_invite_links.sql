-- Invite links for Mistia Family.
-- Phase constraints: no Universal Links, no push notification, no paid Apple capability.

alter table public.family_invites
    add column if not exists token text;

update public.family_invites
set token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-'::text, ''::text)
where token is null;

alter table public.family_invites
    alter column token set not null;

create unique index if not exists family_invites_token_unique
    on public.family_invites(token);

create index if not exists family_invites_token_lookup_idx
    on public.family_invites(token)
    where deleted_at is null;

create or replace function public.family_invite_legacy_code()
returns text
language sql
volatile
as $$
    select upper(substring(replace(gen_random_uuid()::text, '-'::text, ''::text) from 1 for 8));
$$;

create or replace function public.family_invite_token()
returns text
language sql
volatile
as $$
    select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-'::text, ''::text);
$$;

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
    owner_count integer;
    invite_row public.family_invites;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để tạo lời mời.';
    end if;

    if normalized_role not in ('owner', 'member', 'kid') then
        raise exception 'Vai trò lời mời không hợp lệ.';
    end if;

    if not exists (
        select 1
        from public.family_memberships fm
        join public.families f on f.id = fm.family_id
        where fm.family_id = p_family_id
          and fm.user_id = actor_id
          and fm.role = 'owner'
          and fm.deleted_at is null
          and f.deleted_at is null
    ) then
        raise exception 'Chỉ chủ sở hữu mới có thể mời thành viên.';
    end if;

    if normalized_role = 'owner' then
        select count(*) into owner_count
        from public.family_memberships fm
        where fm.family_id = p_family_id
          and fm.role = 'owner'
          and fm.deleted_at is null;

        if owner_count >= 2 then
            raise exception 'Gia đình này đã có tối đa 2 chủ sở hữu.';
        end if;
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

    if already_member_of_family then
        status := 'accepted';
    elsif invite_row.accepted_at is not null then
        status := 'accepted';
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
    owner_count integer;
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

    select *
    into family_row
    from public.families f
    where f.id = invite_row.family_id
      and f.deleted_at is null
    limit 1;

    if family_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
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

    if invite_row.default_role = 'owner' then
        select count(*) into owner_count
        from public.family_memberships fm
        where fm.family_id = invite_row.family_id
          and fm.role = 'owner'
          and fm.deleted_at is null;

        if owner_count >= 2 then
            raise exception 'Gia đình này đã có tối đa 2 chủ sở hữu.';
        end if;
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
        invite_row.default_role in ('owner', 'member'),
        invite_row.default_role = 'owner',
        false,
        invite_row.default_role in ('owner', 'kid'),
        invite_row.default_role = 'owner',
        invite_row.default_role = 'owner',
        false
    )
    returning * into membership_row;

    update public.family_invites fi
    set accepted_at = timezone('utc'::text, now()),
        accepted_by_user_id = actor_id
    where fi.id = invite_row.id;

    actor_name := coalesce(
        (
            select nullif(display_name, '')
            from public.user_profiles up
            where up.user_id = actor_id
            limit 1
        ),
        'Một thành viên'
    );

    for owner_row in
        select user_id
        from public.family_memberships fm
        where fm.family_id = invite_row.family_id
          and fm.role = 'owner'
          and fm.deleted_at is null
          and fm.user_id <> actor_id
    loop
        insert into public.family_notifications (
            source_event_key,
            family_id,
            user_id,
            actor_user_id,
            kind,
            action_state,
            title,
            body,
            metadata
        )
        values (
            'family_invite.accepted.' || invite_row.id::text || '.' || owner_row.user_id::text,
            invite_row.family_id,
            owner_row.user_id,
            actor_id,
            'family_activity',
            'informational',
            'Gia đình',
            actor_name || ' đã tham gia gia đình ' || family_row.name || '.',
            jsonb_build_object('invite_id', invite_row.id::text, 'joined_user_id', actor_id::text)
        )
        on conflict (source_event_key)
        do update set id = family_notifications.id;
    end loop;

    return membership_row;
end;
$$;

create or replace function public.revoke_family_invite(
    p_invite_id uuid
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
        raise exception 'Bạn cần đăng nhập để thu hồi lời mời.';
    end if;

    select *
    into invite_row
    from public.family_invites fi
    where fi.id = p_invite_id
      and fi.deleted_at is null
    for update;

    if invite_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    if not exists (
        select 1
        from public.family_memberships fm
        where fm.family_id = invite_row.family_id
          and fm.user_id = actor_id
          and fm.role = 'owner'
          and fm.deleted_at is null
    ) then
        raise exception 'Chỉ chủ sở hữu mới có thể thu hồi lời mời.';
    end if;

    if invite_row.accepted_at is not null then
        raise exception 'Lời mời này đã được sử dụng.';
    end if;

    update public.family_invites fi
    set revoked_at = coalesce(fi.revoked_at, timezone('utc'::text, now()))
    where fi.id = p_invite_id
    returning * into invite_row;

    return invite_row;
end;
$$;

grant execute on function public.create_family_invite_link(uuid, text, timestamptz) to authenticated;
grant execute on function public.preview_family_invite(text) to authenticated;
grant execute on function public.accept_family_invite(text) to authenticated;
grant execute on function public.revoke_family_invite(uuid) to authenticated;
