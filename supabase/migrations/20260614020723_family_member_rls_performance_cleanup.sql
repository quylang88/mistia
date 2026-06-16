-- Keep family/member access semantics unchanged while avoiding per-row auth
-- initialization and duplicate permissive policy evaluation.

drop policy if exists "user_profiles_select_own" on public.user_profiles;
drop policy if exists "user_profiles_select_family_members" on public.user_profiles;
create policy "user_profiles_select_accessible"
on public.user_profiles
for select
to authenticated
using (
  (select auth.uid()) = user_id
  or user_id in (
    select public.my_active_family_member_user_ids()
  )
);

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "families_owner_all" on public.families;
drop policy if exists "families_member_select" on public.families;
drop policy if exists "families_invite_select" on public.families;

create policy "families_accessible_select"
on public.families
for select
to authenticated
using (
  public.has_active_invite(id)
  or (
    deleted_at is null
    and (
      (select auth.uid()) = owner_user_id
      or public.is_family_member(id)
    )
  )
);

create policy "families_owner_insert"
on public.families
for insert
to authenticated
with check ((select auth.uid()) = owner_user_id);

create policy "families_owner_update"
on public.families
for update
to authenticated
using (
  (select auth.uid()) = owner_user_id
  and deleted_at is null
)
with check ((select auth.uid()) = owner_user_id);

create policy "families_owner_delete"
on public.families
for delete
to authenticated
using (
  (select auth.uid()) = owner_user_id
  and deleted_at is null
);

drop policy if exists "family_memberships_self_select" on public.family_memberships;
drop policy if exists "family_memberships_family_roster_select" on public.family_memberships;
create policy "family_memberships_accessible_select"
on public.family_memberships
for select
to authenticated
using (
  deleted_at is null
  and (
    user_id = (select auth.uid())
    or public.is_family_member(family_id)
  )
);

drop policy if exists "family_memberships_creator_self_insert" on public.family_memberships;
drop policy if exists "family_memberships_owner_insert" on public.family_memberships;
create policy "family_memberships_owner_insert"
on public.family_memberships
for insert
to authenticated
with check (public.is_family_owner(family_id));

drop policy if exists "family_invites_owner_all" on public.family_invites;
drop policy if exists "family_invites_read_by_code" on public.family_invites;
drop policy if exists "family_invites_accept_update" on public.family_invites;

create policy "family_invites_read_by_code"
on public.family_invites
for select
to authenticated
using (deleted_at is null);

create policy "family_invites_owner_insert"
on public.family_invites
for insert
to authenticated
with check (public.is_family_owner(family_id));

create policy "family_invites_update"
on public.family_invites
for update
to authenticated
using (
  (
    deleted_at is null
    and public.is_family_owner(family_id)
  )
  or (
    accepted_at is null
    and revoked_at is null
    and expires_at >= now()
  )
)
with check (
  public.is_family_owner(family_id)
  or accepted_by_user_id = (select auth.uid())
);

create policy "family_invites_owner_delete"
on public.family_invites
for delete
to authenticated
using (
  deleted_at is null
  and public.is_family_owner(family_id)
);

drop policy if exists "family_permission_requests_participant_select"
on public.family_permission_requests;
create policy "family_permission_requests_participant_select"
on public.family_permission_requests
for select
to authenticated
using (
  requester_user_id = (select auth.uid())
  or recipient_user_id = (select auth.uid())
);

drop policy if exists "family_permission_grants_member_select"
on public.family_permission_grants;
create policy "family_permission_grants_member_select"
on public.family_permission_grants
for select
to authenticated
using (
  public.active_family_member_exists(family_id, (select auth.uid()))
  and (
    grantee_user_id = (select auth.uid())
    or owner_user_id = (select auth.uid())
    or public.is_family_owner(family_id)
  )
);

drop policy if exists "family_notifications_recipient_select"
on public.family_notifications;
create policy "family_notifications_recipient_select"
on public.family_notifications
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "family_notifications_recipient_update"
on public.family_notifications;
create policy "family_notifications_recipient_update"
on public.family_notifications
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
