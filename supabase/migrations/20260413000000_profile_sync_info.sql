alter table public.user_profiles
add column if not exists last_sync_at timestamptz,
add column if not exists last_sync_status text;
