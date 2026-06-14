create table if not exists public.account_devices (
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null,
    session_id uuid,
    device_name text not null default '',
    model_identifier text not null default '',
    model_display_name text not null default '',
    system_name text not null default '',
    system_version text not null default '',
    app_version text not null default '',
    app_build text not null default '',
    signed_in_at timestamptz not null default timezone('utc'::text, now()),
    last_seen_at timestamptz not null default timezone('utc'::text, now()),
    signed_out_at timestamptz,
    forget_at timestamptz,
    remote_sign_out_requested_at timestamptz,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now()),
    primary key (user_id, device_id)
);

create index if not exists account_devices_user_last_seen_idx
on public.account_devices(user_id, last_seen_at desc);

create index if not exists account_devices_user_forget_idx
on public.account_devices(user_id, forget_at);

drop trigger if exists account_devices_set_updated_at on public.account_devices;
create trigger account_devices_set_updated_at before update on public.account_devices
for each row execute function public.set_updated_at();

alter table public.account_devices enable row level security;

grant select, insert, update, delete on table public.account_devices to authenticated;
grant all on table public.account_devices to service_role;

drop policy if exists "account_devices_owner_select" on public.account_devices;
create policy "account_devices_owner_select"
on public.account_devices
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "account_devices_owner_insert" on public.account_devices;
create policy "account_devices_owner_insert"
on public.account_devices
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "account_devices_owner_update" on public.account_devices;
create policy "account_devices_owner_update"
on public.account_devices
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "account_devices_owner_delete" on public.account_devices;
create policy "account_devices_owner_delete"
on public.account_devices
for delete
to authenticated
using ((select auth.uid()) = user_id);

notify pgrst, 'reload schema';
