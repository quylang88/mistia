-- Overview layout is a per-user preference. The existing user_profiles RLS
-- lets only the owner write their row while active family members can read it.

alter table public.user_profiles
    add column if not exists overview_section_config jsonb,
    add column if not exists overview_section_config_updated_at timestamptz;

alter table public.user_profiles
    drop constraint if exists user_profiles_overview_section_config_is_array;

alter table public.user_profiles
    add constraint user_profiles_overview_section_config_is_array
    check (
        overview_section_config is null
        or jsonb_typeof(overview_section_config) = 'array'
    );

alter table public.user_profiles
    drop constraint if exists user_profiles_overview_section_config_timestamp_pair;

alter table public.user_profiles
    add constraint user_profiles_overview_section_config_timestamp_pair
    check (
        (overview_section_config is null and overview_section_config_updated_at is null)
        or
        (overview_section_config is not null and overview_section_config_updated_at is not null)
    );

comment on column public.user_profiles.overview_section_config is
    'Ordered, per-user Overview section visibility preferences readable by active family members.';

comment on column public.user_profiles.overview_section_config_updated_at is
    'Client modification time used to resolve Overview preference changes across devices.';
