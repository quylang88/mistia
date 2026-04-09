create table if not exists public.user_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default '',
    avatar_url text,
    birthday date,
    created_at timestamptz not null default timezone('utc'::text, now()),
    updated_at timestamptz not null default timezone('utc'::text, now())
);

drop trigger if exists user_profiles_set_updated_at on public.user_profiles;
create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row
execute function public.set_updated_at();

alter table public.user_profiles enable row level security;

drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own"
on public.user_profiles
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    insert into public.user_profiles (
        user_id,
        display_name,
        avatar_url
    )
    values (
        new.id,
        coalesce(
            nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
            nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
            nullif(split_part(new.email, '@', 1), ''),
            'Mistia'
        ),
        nullif(
            coalesce(
                new.raw_user_meta_data ->> 'avatar_url',
                new.raw_user_meta_data ->> 'picture'
            ),
            ''
        )
    )
    on conflict (user_id) do nothing;
    return new;
end;
$$;

insert into public.user_profiles (
    user_id,
    display_name,
    avatar_url,
    created_at,
    updated_at
)
select
    users.id,
    coalesce(
        nullif(trim(users.raw_user_meta_data ->> 'display_name'), ''),
        nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
        nullif(split_part(users.email, '@', 1), ''),
        'Mistia'
    ),
    nullif(
        coalesce(
            users.raw_user_meta_data ->> 'avatar_url',
            users.raw_user_meta_data ->> 'picture'
        ),
        ''
    ),
    timezone('utc'::text, now()),
    timezone('utc'::text, now())
from auth.users as users
on conflict (user_id) do nothing;

drop trigger if exists on_auth_user_created_user_profile on auth.users;
create trigger on_auth_user_created_user_profile
after insert on auth.users
for each row
execute function public.handle_new_user_profile();

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'profile-avatars',
    'profile-avatars',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do update
set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "profile_avatars_public_read" on storage.objects;
create policy "profile_avatars_public_read"
on storage.objects
for select
to public
using (bucket_id = 'profile-avatars');

drop policy if exists "profile_avatars_insert_own" on storage.objects;
create policy "profile_avatars_insert_own"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "profile_avatars_update_own" on storage.objects;
create policy "profile_avatars_update_own"
on storage.objects
for update
to authenticated
using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "profile_avatars_delete_own" on storage.objects;
create policy "profile_avatars_delete_own"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
);
