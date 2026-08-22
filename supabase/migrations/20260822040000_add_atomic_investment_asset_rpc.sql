-- Route Investment asset create/edit/delete through server-authoritative RPCs.
-- Asset mutations preserve FIFO history by making channel and currency immutable
-- after the first trade, while still allowing product metadata and images to change.

create or replace function public.mutate_investment_asset(
    p_asset jsonb,
    p_expected_version bigint default null,
    p_force boolean default false
)
returns setof public.investment_assets
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    incoming public.investment_assets%rowtype;
    existing public.investment_assets%rowtype;
    channel_row public.investment_channels%rowtype;
    required_scope text;
    now_value timestamptz := timezone('utc'::text, now());
begin
    if actor_id is null then raise exception 'Not authenticated'; end if;

    incoming := jsonb_populate_record(null::public.investment_assets, p_asset);
    incoming.name := btrim(incoming.name);
    incoming.currency_code := upper(btrim(incoming.currency_code));

    if incoming.id is null
       or incoming.user_id is null
       or incoming.channel_id is null
       or nullif(incoming.name, '') is null
       or length(incoming.currency_code) <> 3 then
        raise exception 'Invalid investment product input';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('investment-asset:' || incoming.id::text, 0));
    select * into existing
    from public.investment_assets
    where id = incoming.id
    for update;

    required_scope := case when existing.id is null then 'create' else 'edit' end;
    if not public.has_investment_permission(incoming.user_id, required_scope) then
        raise exception 'Investment % permission is required', required_scope;
    end if;
    if existing.id is not null and existing.user_id <> incoming.user_id then
        raise exception 'Investment ownership is immutable';
    end if;
    if existing.id is not null
       and p_expected_version is not null
       and existing.sync_version <> p_expected_version
       and not p_force then
        return;
    end if;
    if existing.id is null
       and p_expected_version is not null
       and p_expected_version <> 0
       and not p_force then
        return;
    end if;
    if existing.id is null and incoming.deleted_at is not null then
        raise exception 'A deleted investment product cannot be created';
    end if;

    if incoming.deleted_at is null then
        select * into channel_row
        from public.investment_channels
        where id = incoming.channel_id
          and user_id = incoming.user_id
          and deleted_at is null
          and is_archived = false
        for update;
        if channel_row.id is null then
            raise exception 'Investment channel not found';
        end if;
    end if;

    if existing.id is not null
       and exists (
           select 1 from public.investment_trades trade where trade.asset_id = existing.id
       )
       and (
           existing.channel_id is distinct from incoming.channel_id
           or upper(existing.currency_code) is distinct from incoming.currency_code
       ) then
        raise exception 'Product channel and currency are immutable after history exists';
    end if;

    incoming.archived_at := case
        when coalesce(incoming.is_archived, false) then coalesce(incoming.archived_at, now_value)
        else null
    end;

    if existing.id is null then
        insert into public.investment_assets (
            id, user_id, channel_id, name, currency_code, image_path, sort_order,
            is_archived, archived_at, created_at, updated_at, deleted_at,
            sync_version, last_modified_by_device_id
        ) values (
            incoming.id,
            incoming.user_id,
            incoming.channel_id,
            incoming.name,
            incoming.currency_code,
            incoming.image_path,
            coalesce(incoming.sort_order, 0),
            coalesce(incoming.is_archived, false),
            incoming.archived_at,
            coalesce(incoming.created_at, now_value),
            now_value,
            null,
            1,
            incoming.last_modified_by_device_id
        );
    else
        update public.investment_assets set
            channel_id = incoming.channel_id,
            name = incoming.name,
            currency_code = incoming.currency_code,
            image_path = incoming.image_path,
            sort_order = coalesce(incoming.sort_order, existing.sort_order),
            is_archived = coalesce(incoming.is_archived, false),
            archived_at = incoming.archived_at,
            updated_at = now_value,
            deleted_at = incoming.deleted_at,
            sync_version = existing.sync_version + 1,
            last_modified_by_device_id = incoming.last_modified_by_device_id
        where id = existing.id;
    end if;

    return query
    select * from public.investment_assets where id = incoming.id;
end;
$$;

revoke execute on function public.mutate_investment_asset(jsonb, bigint, boolean) from public, anon;
grant execute on function public.mutate_investment_asset(jsonb, bigint, boolean) to authenticated;

create or replace function public.delete_investment_asset(
    p_asset_id uuid,
    p_owner_user_id uuid,
    p_expected_version bigint,
    p_modified_at timestamptz,
    p_device_id uuid
)
returns setof public.investment_assets
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    existing public.investment_assets%rowtype;
    now_value timestamptz := coalesce(p_modified_at, timezone('utc'::text, now()));
begin
    if actor_id is null then raise exception 'Not authenticated'; end if;
    if p_asset_id is null or p_owner_user_id is null then
        raise exception 'Incomplete investment product delete';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('investment-asset:' || p_asset_id::text, 0));
    select * into existing
    from public.investment_assets
    where id = p_asset_id and user_id = p_owner_user_id
    for update;
    if existing.id is null then return; end if;
    if not public.has_investment_permission(p_owner_user_id, 'edit') then
        raise exception 'Investment edit permission is required';
    end if;
    if existing.sync_version <> p_expected_version then return; end if;

    update public.investment_assets set
        deleted_at = now_value,
        updated_at = now_value,
        sync_version = existing.sync_version + 1,
        last_modified_by_device_id = p_device_id
    where id = existing.id;

    return query
    select * from public.investment_assets where id = existing.id;
end;
$$;

revoke execute on function public.delete_investment_asset(uuid, uuid, bigint, timestamptz, uuid) from public, anon;
grant execute on function public.delete_investment_asset(uuid, uuid, bigint, timestamptz, uuid) to authenticated;
