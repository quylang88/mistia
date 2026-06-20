-- Harden the currently exposed family/auth RPC surface without changing app
-- flows. SECURITY DEFINER app/RLS helpers still needed by authenticated users
-- keep explicit authenticated grants; anonymous/public execution is removed.

-- Clear mutable search_path advisor warnings on non-definer helpers/triggers.
alter function public.family_invite_legacy_code() set search_path = public, extensions;
alter function public.family_invite_token() set search_path = public, extensions;
alter function public.set_updated_at() set search_path = public;
alter function public.mistia_wallet_balance_delta(text, text, text, text, bigint, text) set search_path = public;
alter function public.mistia_set_wallet_current_balance() set search_path = public;
alter function public.mistia_calculate_wallet_current_balance(uuid, uuid, text, bigint) set search_path = public;

-- App-facing authenticated RPCs.
revoke execute on function public.preview_family_invite(text) from public, anon;
grant execute on function public.preview_family_invite(text) to authenticated;

revoke execute on function public.accept_family_invite(text) from public, anon;
grant execute on function public.accept_family_invite(text) to authenticated;

revoke execute on function public.decline_family_invite(text) from public, anon;
grant execute on function public.decline_family_invite(text) to authenticated;

revoke execute on function public.create_family_invite_link(uuid, text, timestamptz) from public, anon;
grant execute on function public.create_family_invite_link(uuid, text, timestamptz) to authenticated;

revoke execute on function public.revoke_family_invite(uuid) from public, anon;
grant execute on function public.revoke_family_invite(uuid) to authenticated;

revoke execute on function public.set_family_permission_grant(uuid, uuid, uuid, text, uuid, text, boolean) from public, anon;
grant execute on function public.set_family_permission_grant(uuid, uuid, uuid, text, uuid, text, boolean) to authenticated;

revoke execute on function public.set_family_planning_manager(uuid, text, uuid) from public, anon;
grant execute on function public.set_family_planning_manager(uuid, text, uuid) to authenticated;

revoke execute on function public.remove_family_member(uuid) from public, anon;
grant execute on function public.remove_family_member(uuid) to authenticated;

revoke execute on function public.transfer_family_owner(uuid, uuid) from public, anon;
grant execute on function public.transfer_family_owner(uuid, uuid) to authenticated;

revoke execute on function public.delete_family(uuid) from public, anon;
grant execute on function public.delete_family(uuid) to authenticated;

revoke execute on function public.create_family_transfer(
  uuid, uuid, uuid, uuid, bigint, bigint, text, text, text, text, timestamptz, text, text, text
) from public, anon;
grant execute on function public.create_family_transfer(
  uuid, uuid, uuid, uuid, bigint, bigint, text, text, text, text, timestamptz, text, text, text
) to authenticated;

revoke execute on function public.create_family_permission_request(
  uuid, uuid, text, uuid, text, text, text, text
) from public, anon;
grant execute on function public.create_family_permission_request(
  uuid, uuid, text, uuid, text, text, text, text
) to authenticated;

revoke execute on function public.respond_family_permission_request(uuid, boolean) from public, anon;
grant execute on function public.respond_family_permission_request(uuid, boolean) to authenticated;

revoke execute on function public.mark_family_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_family_notifications_read(uuid[]) to authenticated;

revoke execute on function public.family_cloud_sync_status(uuid) from public, anon;
grant execute on function public.family_cloud_sync_status(uuid) to authenticated;

revoke execute on function public.create_family_activity_notification(
  uuid, text, uuid, text, text, text, jsonb
) from public, anon;
grant execute on function public.create_family_activity_notification(
  uuid, text, uuid, text, text, text, jsonb
) to authenticated;

revoke execute on function public.consume_receipt_ai_scan_quota(integer) from public, anon;
grant execute on function public.consume_receipt_ai_scan_quota(integer) to authenticated;

-- RLS policy helpers referenced directly by current policies. These must remain
-- executable by authenticated users, or table reads/writes fail during policy
-- evaluation.
revoke execute on function public.active_family_member_exists(uuid, uuid) from public, anon;
grant execute on function public.active_family_member_exists(uuid, uuid) to authenticated;

revoke execute on function public.can_manage_event(uuid, uuid) from public, anon;
grant execute on function public.can_manage_event(uuid, uuid) to authenticated;

revoke execute on function public.can_manage_transaction(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.can_manage_transaction(uuid, uuid, uuid, uuid) to authenticated;

revoke execute on function public.can_operate_wallet(uuid) from public, anon;
grant execute on function public.can_operate_wallet(uuid) to authenticated;

revoke execute on function public.can_read_transaction(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.can_read_transaction(uuid, uuid, uuid, uuid) to authenticated;

revoke execute on function public.can_write_settlement_principal_transaction(
  uuid, uuid, text, text, text, uuid, uuid, uuid, text
) from public, anon;
grant execute on function public.can_write_settlement_principal_transaction(
  uuid, uuid, text, text, text, uuid, uuid, uuid, text
) to authenticated;

revoke execute on function public.has_active_invite(uuid) from public, anon;
grant execute on function public.has_active_invite(uuid) to authenticated;

revoke execute on function public.has_due_occurrence_edit_permission(uuid, text, uuid) from public, anon;
grant execute on function public.has_due_occurrence_edit_permission(uuid, text, uuid) to authenticated;

revoke execute on function public.has_family_finance_view_access(uuid, boolean) from public, anon;
grant execute on function public.has_family_finance_view_access(uuid, boolean) to authenticated;

revoke execute on function public.has_family_permission_grant(uuid, text, uuid, text) from public, anon;
grant execute on function public.has_family_permission_grant(uuid, text, uuid, text) to authenticated;

revoke execute on function public.has_family_wallet_operation_access(uuid) from public, anon;
grant execute on function public.has_family_wallet_operation_access(uuid) to authenticated;

revoke execute on function public.is_family_member(uuid) from public, anon;
grant execute on function public.is_family_member(uuid) to authenticated;

revoke execute on function public.is_family_owner(uuid) from public, anon;
grant execute on function public.is_family_owner(uuid) to authenticated;

revoke execute on function public.my_active_family_member_user_ids() from public, anon;
grant execute on function public.my_active_family_member_user_ids() to authenticated;

revoke execute on function public.transaction_category_matches_owner(uuid, uuid) from public, anon;
grant execute on function public.transaction_category_matches_owner(uuid, uuid) to authenticated;

revoke execute on function public.wallet_owner_user_id(uuid) from public, anon;
grant execute on function public.wallet_owner_user_id(uuid) to authenticated;

-- Internal helpers/triggers not directly called by the app or current RLS
-- policies. Keep them available to their owning database code, but remove direct
-- API execution for anon/authenticated users.
revoke execute on function public.can_manage_event(uuid) from public, anon, authenticated;
revoke execute on function public.family_resource_owner_user_id(text, uuid) from public, anon, authenticated;
revoke execute on function public.handle_new_user_profile() from public, anon, authenticated;
revoke execute on function public.has_family_wallet_access(uuid) from public, anon, authenticated;
revoke execute on function public.is_family_owner_of_user(uuid) from public, anon, authenticated;
revoke execute on function public.mistia_recalculate_wallet_current_balance(uuid) from public, anon, authenticated;
revoke execute on function public.mistia_refresh_wallet_balance_from_credit_card_profile() from public, anon, authenticated;
revoke execute on function public.mistia_refresh_wallet_balances_from_transaction() from public, anon, authenticated;
revoke execute on function public.my_family_ids() from public, anon, authenticated;
revoke execute on function public.my_family_member_user_ids() from public, anon, authenticated;
revoke execute on function public.prevent_family_transfer_mutation() from public, anon, authenticated;
revoke execute on function public.shared_active_family_id(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.user_has_synced_finance_data(uuid) from public, anon, authenticated;

-- Non-definer helpers/triggers: remove public/anon execution. Authenticated
-- remains because wallet/update triggers and invoker helpers call these during
-- ordinary table writes.
revoke execute on function public.family_invite_legacy_code() from public, anon, authenticated;
revoke execute on function public.family_invite_token() from public, anon, authenticated;

revoke execute on function public.set_updated_at() from public, anon;
grant execute on function public.set_updated_at() to authenticated;

revoke execute on function public.mistia_wallet_balance_delta(text, text, text, text, bigint, text) from public, anon;
grant execute on function public.mistia_wallet_balance_delta(text, text, text, text, bigint, text) to authenticated;

revoke execute on function public.mistia_calculate_wallet_current_balance(uuid, uuid, text, bigint) from public, anon;
grant execute on function public.mistia_calculate_wallet_current_balance(uuid, uuid, text, bigint) to authenticated;

revoke execute on function public.mistia_set_wallet_current_balance() from public, anon;
grant execute on function public.mistia_set_wallet_current_balance() to authenticated;

notify pgrst, 'reload schema';
