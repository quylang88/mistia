-- Family ownership and membership management must be atomic.
-- Direct client-side multi-step PATCH calls can lose RLS ownership halfway
-- through a delete-family flow, so owner/member lifecycle changes live here.

grant usage on schema public to authenticated;

grant select, insert, update, delete
on table public.families,
         public.family_memberships,
         public.family_invites
to authenticated;

update public.family_memberships fm
set role = 'member',
    can_view_family_dashboard = true,
    can_view_others = true,
    can_edit_others = false,
    can_view_wallets = true,
    can_view_debts = true,
    can_view_kids = false,
    can_edit_kids = false
from public.families f
where f.id = fm.family_id
  and f.deleted_at is null
  and fm.deleted_at is null
  and fm.role = 'owner'
  and fm.user_id <> f.owner_user_id;

update public.family_memberships fm
set role = 'owner',
    can_view_family_dashboard = true,
    can_view_others = true,
    can_edit_others = false,
    can_view_wallets = true,
    can_view_debts = true,
    can_view_kids = true,
    can_edit_kids = false
from public.families f
where f.id = fm.family_id
  and f.deleted_at is null
  and fm.deleted_at is null
  and fm.user_id = f.owner_user_id;

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
select
    f.id,
    f.owner_user_id,
    'owner',
    true,
    true,
    false,
    true,
    true,
    true,
    false
from public.families f
where f.deleted_at is null
  and not exists (
      select 1
      from public.family_memberships fm
      where fm.family_id = f.id
        and fm.user_id = f.owner_user_id
        and fm.deleted_at is null
  );

create unique index if not exists family_memberships_one_active_owner_per_family
on public.family_memberships(family_id)
where role = 'owner' and deleted_at is null;

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
    invite_row public.family_invites;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để tạo lời mời.';
    end if;

    if normalized_role not in ('member', 'kid') then
        raise exception 'Gia đình chỉ có một chủ sở hữu. Hãy mời thành viên rồi nhượng quyền owner sau.';
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
          and f.owner_user_id = actor_id
    ) then
        raise exception 'Chỉ chủ sở hữu mới có thể mời thành viên.';
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

create or replace function public.remove_family_member(
    p_membership_id uuid
)
returns public.family_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    target_row public.family_memberships;
    family_row public.families;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để thay đổi thành viên gia đình.';
    end if;

    select *
    into target_row
    from public.family_memberships fm
    where fm.id = p_membership_id
      and fm.deleted_at is null
    limit 1;

    if target_row.id is null then
        raise exception 'Không tìm thấy thành viên gia đình.';
    end if;

    select *
    into family_row
    from public.families f
    where f.id = target_row.family_id
      and f.deleted_at is null
    limit 1;

    if family_row.id is null then
        raise exception 'Gia đình này không còn tồn tại.';
    end if;

    if target_row.user_id = actor_id then
        if target_row.role = 'owner' then
            raise exception 'Owner không thể rời gia đình. Hãy xóa gia đình hoặc nhượng quyền owner trước.';
        end if;
    elsif family_row.owner_user_id <> actor_id then
        raise exception 'Chỉ owner mới có thể gỡ thành viên khác khỏi gia đình.';
    elsif target_row.role = 'owner' then
        raise exception 'Không thể gỡ owner hiện tại khỏi gia đình.';
    end if;

    update public.family_memberships fm
    set deleted_at = timezone('utc'::text, now())
    where fm.id = target_row.id
    returning * into target_row;

    update public.family_wallet_access_grants fwag
    set revoked_at = coalesce(fwag.revoked_at, timezone('utc'::text, now()))
    where fwag.family_id = target_row.family_id
      and fwag.revoked_at is null
      and (
          fwag.grantee_user_id = target_row.user_id
          or fwag.target_user_id = target_row.user_id
      );

    return target_row;
end;
$$;

create or replace function public.transfer_family_owner(
    p_family_id uuid,
    p_new_owner_membership_id uuid
)
returns public.family_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    previous_owner_row public.family_memberships;
    new_owner_row public.family_memberships;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để nhượng quyền owner.';
    end if;

    select fm.*
    into previous_owner_row
    from public.family_memberships fm
    join public.families f on f.id = fm.family_id
    where fm.family_id = p_family_id
      and fm.user_id = actor_id
      and fm.role = 'owner'
      and fm.deleted_at is null
      and f.deleted_at is null
      and f.owner_user_id = actor_id
    limit 1;

    if previous_owner_row.id is null then
        raise exception 'Chỉ owner hiện tại mới có thể nhượng quyền owner.';
    end if;

    select *
    into new_owner_row
    from public.family_memberships fm
    where fm.id = p_new_owner_membership_id
      and fm.family_id = p_family_id
      and fm.deleted_at is null
    limit 1;

    if new_owner_row.id is null then
        raise exception 'Không tìm thấy thành viên nhận quyền owner.';
    end if;

    if new_owner_row.user_id = actor_id then
        raise exception 'Bạn đang là owner của gia đình này.';
    end if;

    if new_owner_row.role <> 'member' then
        raise exception 'Chỉ có thể nhượng quyền owner cho thành viên.';
    end if;

    update public.family_memberships fm
    set role = 'member',
        can_view_family_dashboard = true,
        can_view_others = true,
        can_edit_others = false,
        can_view_wallets = true,
        can_view_debts = true,
        can_view_kids = false,
        can_edit_kids = false
    where fm.id = previous_owner_row.id;

    update public.family_memberships fm
    set role = 'owner',
        can_view_family_dashboard = true,
        can_view_others = true,
        can_edit_others = false,
        can_view_wallets = true,
        can_view_debts = true,
        can_view_kids = true,
        can_edit_kids = false
    where fm.id = new_owner_row.id
    returning * into new_owner_row;

    update public.families f
    set owner_user_id = new_owner_row.user_id
    where f.id = p_family_id
      and f.owner_user_id = actor_id
      and f.deleted_at is null;

    return new_owner_row;
end;
$$;

create or replace function public.delete_family(
    p_family_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    now_utc timestamptz := timezone('utc'::text, now());
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để xóa gia đình.';
    end if;

    if not exists (
        select 1
        from public.families f
        join public.family_memberships fm on fm.family_id = f.id
        where f.id = p_family_id
          and f.owner_user_id = actor_id
          and f.deleted_at is null
          and fm.user_id = actor_id
          and fm.role = 'owner'
          and fm.deleted_at is null
    ) then
        raise exception 'Chỉ owner hiện tại mới có thể xóa gia đình.';
    end if;

    update public.family_invites fi
    set deleted_at = coalesce(fi.deleted_at, now_utc)
    where fi.family_id = p_family_id;

    update public.family_wallet_access_grants fwag
    set revoked_at = coalesce(fwag.revoked_at, now_utc)
    where fwag.family_id = p_family_id;

    update public.family_memberships fm
    set deleted_at = coalesce(fm.deleted_at, now_utc)
    where fm.family_id = p_family_id;

    update public.families f
    set deleted_at = now_utc
    where f.id = p_family_id;
end;
$$;

drop policy if exists "family_memberships_update_policy" on public.family_memberships;
drop policy if exists "family_memberships_owner_update" on public.family_memberships;
create policy "family_memberships_update_policy"
on public.family_memberships
for update
to authenticated
using (
    deleted_at is null
    and public.is_family_owner(family_id)
)
with check (
    public.is_family_owner(family_id)
);

drop policy if exists "family_memberships_delete_policy" on public.family_memberships;
drop policy if exists "family_memberships_owner_delete" on public.family_memberships;
create policy "family_memberships_delete_policy"
on public.family_memberships
for delete
to authenticated
using (
    deleted_at is null
    and public.is_family_owner(family_id)
);

grant execute on function public.create_family_invite_link(uuid, text, timestamptz) to authenticated;
grant execute on function public.accept_family_invite(text) to authenticated;
grant execute on function public.remove_family_member(uuid) to authenticated;
grant execute on function public.transfer_family_owner(uuid, uuid) to authenticated;
grant execute on function public.delete_family(uuid) to authenticated;
