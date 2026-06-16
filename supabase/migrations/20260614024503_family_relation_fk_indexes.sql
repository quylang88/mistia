-- Cover family relation foreign keys so parent updates/deletes and relation
-- lookups do not require full-table scans as family data grows.

create index if not exists family_invites_accepted_by_user_id_idx
on public.family_invites (accepted_by_user_id);

create index if not exists family_invites_created_by_user_id_idx
on public.family_invites (created_by_user_id);

create index if not exists family_invites_declined_by_user_id_idx
on public.family_invites (declined_by_user_id);

create index if not exists family_notifications_actor_user_id_idx
on public.family_notifications (actor_user_id);

create index if not exists family_notifications_family_id_idx
on public.family_notifications (family_id);

create index if not exists family_notifications_permission_request_id_idx
on public.family_notifications (permission_request_id);

create index if not exists family_permission_grants_granted_by_user_id_idx
on public.family_permission_grants (granted_by_user_id);

create index if not exists family_permission_grants_owner_user_id_idx
on public.family_permission_grants (owner_user_id);

create index if not exists family_permission_requests_responded_by_user_id_idx
on public.family_permission_requests (responded_by_user_id);
