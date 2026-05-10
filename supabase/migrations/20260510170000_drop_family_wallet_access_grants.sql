-- family_permission_grants now owns wallet use/edit permissions. Keep one final
-- active backfill for databases that received legacy wallet grants after the
-- first granular-permissions migration, then remove the obsolete table.

do $$
begin
    if to_regclass('public.family_wallet_access_grants') is not null then
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
            null
        from public.family_wallet_access_grants g
        join public.ledger_wallets w
          on w.user_id = g.target_user_id
        where g.revoked_at is null
          and w.deleted_at is null
        on conflict do nothing;
    end if;
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
    now_utc timestamptz := timezone('utc'::text, now());
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
    set deleted_at = now_utc
    where fm.id = target_row.id
    returning * into target_row;

    update public.family_permission_grants fpg
    set revoked_at = coalesce(fpg.revoked_at, now_utc),
        updated_at = now_utc
    where fpg.family_id = target_row.family_id
      and fpg.revoked_at is null
      and (
          fpg.grantee_user_id = target_row.user_id
          or fpg.owner_user_id = target_row.user_id
      );

    return target_row;
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

    update public.family_permission_grants fpg
    set revoked_at = coalesce(fpg.revoked_at, now_utc),
        updated_at = now_utc
    where fpg.family_id = p_family_id
      and fpg.revoked_at is null;

    update public.family_memberships fm
    set deleted_at = coalesce(fm.deleted_at, now_utc)
    where fm.family_id = p_family_id;

    update public.families f
    set deleted_at = now_utc
    where f.id = p_family_id;
end;
$$;

grant execute on function public.remove_family_member(uuid) to authenticated;
grant execute on function public.delete_family(uuid) to authenticated;

drop table if exists public.family_wallet_access_grants;
