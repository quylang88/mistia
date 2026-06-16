create table if not exists public.receipt_ai_daily_usage (
    user_id uuid not null references auth.users(id) on delete cascade,
    usage_date date not null,
    used_count integer not null default 0 check (used_count >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id, usage_date)
);

alter table public.receipt_ai_daily_usage enable row level security;

drop policy if exists "receipt_ai_daily_usage_select_own" on public.receipt_ai_daily_usage;
create policy "receipt_ai_daily_usage_select_own"
on public.receipt_ai_daily_usage
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.consume_receipt_ai_scan_quota(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id uuid := auth.uid();
    v_reset_time_zone text := 'Asia/Tokyo';
    v_usage_date date;
    v_retry_after timestamptz;
    v_limit integer;
    v_used_count integer;
    v_remaining_count integer;
begin
    if v_user_id is null then
        raise exception 'Not authenticated' using errcode = '28000';
    end if;

    v_usage_date := (now() at time zone v_reset_time_zone)::date;
    v_retry_after := ((v_usage_date + 1)::timestamp at time zone v_reset_time_zone);
    v_limit := greatest(coalesce(p_limit, 20), 0);

    if v_limit <= 0 then
        select usage.used_count
        into v_used_count
        from public.receipt_ai_daily_usage as usage
        where usage.user_id = v_user_id
          and usage.usage_date = v_usage_date;

        return jsonb_build_object(
            'allowed', false,
            'used_count', coalesce(v_used_count, 0),
            'limit_count', 0,
            'remaining_count', 0,
            'usage_date', v_usage_date,
            'reset_time_zone', v_reset_time_zone,
            'retry_after', v_retry_after
        );
    end if;

    insert into public.receipt_ai_daily_usage as usage (
        user_id,
        usage_date,
        used_count,
        created_at,
        updated_at
    )
    values (
        v_user_id,
        v_usage_date,
        1,
        now(),
        now()
    )
    on conflict (user_id, usage_date) do update
    set used_count = usage.used_count + 1,
        updated_at = now()
    where usage.used_count < v_limit
    returning used_count into v_used_count;

    if v_used_count is null then
        select usage.used_count
        into v_used_count
        from public.receipt_ai_daily_usage as usage
        where usage.user_id = v_user_id
          and usage.usage_date = v_usage_date;

        v_used_count := coalesce(v_used_count, 0);
        v_remaining_count := greatest(v_limit - v_used_count, 0);

        return jsonb_build_object(
            'allowed', false,
            'used_count', v_used_count,
            'limit_count', v_limit,
            'remaining_count', v_remaining_count,
            'usage_date', v_usage_date,
            'reset_time_zone', v_reset_time_zone,
            'retry_after', v_retry_after
        );
    end if;

    v_remaining_count := greatest(v_limit - v_used_count, 0);

    return jsonb_build_object(
        'allowed', true,
        'used_count', v_used_count,
        'limit_count', v_limit,
        'remaining_count', v_remaining_count,
        'usage_date', v_usage_date,
        'reset_time_zone', v_reset_time_zone,
        'retry_after', v_retry_after
    );
end;
$$;

grant select on public.receipt_ai_daily_usage to authenticated;
grant execute on function public.consume_receipt_ai_scan_quota(integer) to authenticated;

notify pgrst, 'reload schema';
