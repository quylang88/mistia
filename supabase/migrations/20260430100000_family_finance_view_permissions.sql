-- Repair family finance access after family creation and invite acceptance.
--
-- Product rule:
-- - Owner/member can view family finance rows for visible members.
-- - Viewing is not editing/operating. Cross-member wallet operation still
--   requires an approved family_wallet_access_grant.
-- - Kids remain hidden unless the viewer has can_view_kids.

grant usage on schema public to authenticated;

grant select, insert, update, delete
on table public.ledger_wallets,
         public.credit_card_profiles,
         public.transaction_categories,
         public.ledger_transactions,
         public.budget_plans,
         public.savings_goals,
         public.recurring_bill_plans,
         public.installment_plans,
         public.due_occurrence_records
to authenticated;

update public.family_memberships
set can_view_family_dashboard = true,
    can_view_others = true,
    can_edit_others = false,
    can_view_wallets = true,
    can_view_debts = true,
    can_edit_kids = false
where role in ('owner', 'member')
  and deleted_at is null;

update public.family_memberships
set can_view_kids = true
where role = 'owner'
  and deleted_at is null;

create or replace function public.has_family_finance_view_access(
    target_user_id uuid,
    require_wallet_scope boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = target_user_id
        or exists (
            select 1
            from public.family_memberships viewer_membership
            join public.family_memberships target_membership
              on target_membership.family_id = viewer_membership.family_id
            join public.families f
              on f.id = viewer_membership.family_id
            where viewer_membership.user_id = auth.uid()
              and target_membership.user_id = target_user_id
              and viewer_membership.deleted_at is null
              and target_membership.deleted_at is null
              and f.deleted_at is null
              and viewer_membership.can_view_others = true
              and (
                  require_wallet_scope = false
                  or viewer_membership.can_view_wallets = true
              )
              and (
                  target_membership.role <> 'kid'
                  or viewer_membership.can_view_kids = true
              )
        );
$$;

create or replace function public.has_family_wallet_access(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.has_family_finance_view_access(target_user_id, true);
$$;

create or replace function public.has_family_wallet_operation_access(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() = target_user_id
        or exists (
            select 1
            from public.family_wallet_access_grants g
            join public.families f
              on f.id = g.family_id
            join public.family_memberships grantee_membership
              on grantee_membership.family_id = g.family_id
             and grantee_membership.user_id = g.grantee_user_id
            join public.family_memberships target_membership
              on target_membership.family_id = g.family_id
             and target_membership.user_id = g.target_user_id
            where g.grantee_user_id = auth.uid()
              and g.target_user_id = target_user_id
              and g.revoked_at is null
              and f.deleted_at is null
              and grantee_membership.deleted_at is null
              and target_membership.deleted_at is null
        );
$$;

create or replace function public.can_operate_wallet(target_wallet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.ledger_wallets w
        where w.id = target_wallet_id
          and public.has_family_wallet_operation_access(w.user_id)
    );
$$;

drop policy if exists "wallets_family_member_select" on public.ledger_wallets;
drop policy if exists "wallets_family_access_select" on public.ledger_wallets;
create policy "wallets_family_access_select"
on public.ledger_wallets
for select
to authenticated
using (public.has_family_finance_view_access(user_id, true));

drop policy if exists "credit_card_profiles_family_access_select" on public.credit_card_profiles;
create policy "credit_card_profiles_family_access_select"
on public.credit_card_profiles
for select
to authenticated
using (public.has_family_finance_view_access(user_id, true));

drop policy if exists "categories_family_member_select" on public.transaction_categories;
drop policy if exists "categories_family_access_select" on public.transaction_categories;
create policy "categories_family_access_select"
on public.transaction_categories
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

drop policy if exists "budget_plans_family_access_select" on public.budget_plans;
create policy "budget_plans_family_access_select"
on public.budget_plans
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

drop policy if exists "savings_goals_family_access_select" on public.savings_goals;
create policy "savings_goals_family_access_select"
on public.savings_goals
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

drop policy if exists "recurring_bill_plans_family_access_select" on public.recurring_bill_plans;
create policy "recurring_bill_plans_family_access_select"
on public.recurring_bill_plans
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

drop policy if exists "installment_plans_family_access_select" on public.installment_plans;
create policy "installment_plans_family_access_select"
on public.installment_plans
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

drop policy if exists "due_occurrence_records_family_access_select" on public.due_occurrence_records;
create policy "due_occurrence_records_family_access_select"
on public.due_occurrence_records
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));

create or replace function public.accept_family_invite(
    p_token text
)
returns public.family_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    invite_row public.family_invites;
    family_row public.families;
    existing_same_family public.family_memberships;
    existing_other_family_id uuid;
    owner_count integer;
    membership_row public.family_memberships;
    owner_row record;
    actor_name text;
begin
    if actor_id is null then
        raise exception 'Bạn cần đăng nhập để tham gia gia đình.';
    end if;

    select *
    into invite_row
    from public.family_invites fi
    where fi.token = trim(p_token)
      and fi.deleted_at is null
    for update;

    if invite_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    select *
    into family_row
    from public.families f
    where f.id = invite_row.family_id
      and f.deleted_at is null
    limit 1;

    if family_row.id is null then
        raise exception 'Lời mời này không còn hợp lệ.';
    end if;

    if invite_row.revoked_at is not null then
        raise exception 'Lời mời này đã bị thu hồi.';
    end if;

    if invite_row.accepted_at is not null then
        raise exception 'Lời mời này đã được sử dụng.';
    end if;

    if invite_row.expires_at < timezone('utc'::text, now()) then
        raise exception 'Lời mời đã hết hạn. Vui lòng yêu cầu người mời gửi lại link mới.';
    end if;

    select *
    into existing_same_family
    from public.family_memberships fm
    where fm.family_id = invite_row.family_id
      and fm.user_id = actor_id
      and fm.deleted_at is null
    limit 1;

    if existing_same_family.id is not null then
        raise exception 'Bạn đã là thành viên của gia đình này.';
    end if;

    select family_id
    into existing_other_family_id
    from public.family_memberships fm
    where fm.user_id = actor_id
      and fm.family_id <> invite_row.family_id
      and fm.deleted_at is null
    limit 1;

    if existing_other_family_id is not null then
        raise exception 'Tài khoản này hiện đã thuộc một gia đình khác. Vui lòng rời gia đình hiện tại trước khi tham gia gia đình mới.';
    end if;

    if invite_row.default_role = 'owner' then
        select count(*) into owner_count
        from public.family_memberships fm
        where fm.family_id = invite_row.family_id
          and fm.role = 'owner'
          and fm.deleted_at is null;

        if owner_count >= 2 then
            raise exception 'Gia đình này đã có tối đa 2 chủ sở hữu.';
        end if;
    end if;

    insert into public.family_memberships (
        family_id,
        user_id,
        role,
        can_view_family_dashboard,
        can_view_others,
        can_edit_others,
        can_view_wallets,
        can_view_debts,
        can_view_kids,
        can_edit_kids
    )
    values (
        invite_row.family_id,
        actor_id,
        invite_row.default_role,
        invite_row.default_role in ('owner', 'member'),
        invite_row.default_role in ('owner', 'member'),
        false,
        invite_row.default_role in ('owner', 'member'),
        invite_row.default_role in ('owner', 'member'),
        invite_row.default_role = 'owner',
        false
    )
    returning * into membership_row;

    update public.family_invites fi
    set accepted_at = timezone('utc'::text, now()),
        accepted_by_user_id = actor_id
    where fi.id = invite_row.id;

    select up.display_name
    into actor_name
    from public.user_profiles up
    where up.user_id = actor_id
    limit 1;

    for owner_row in
        select fm.user_id
        from public.family_memberships fm
        where fm.family_id = invite_row.family_id
          and fm.role = 'owner'
          and fm.user_id <> actor_id
          and fm.deleted_at is null
    loop
        insert into public.family_notifications (
            source_event_key,
            family_id,
            user_id,
            actor_user_id,
            kind,
            resource_type,
            action_state,
            title,
            body,
            metadata
        )
        values (
            'family-member-joined:' || invite_row.family_id::text || ':' || actor_id::text || ':' || owner_row.user_id::text,
            invite_row.family_id,
            owner_row.user_id,
            actor_id,
            'family_activity',
            'permission',
            'informational',
            'Thành viên mới đã tham gia',
            coalesce(nullif(actor_name, ''), 'Một thành viên') || ' vừa tham gia gia đình.',
            jsonb_build_object('member_user_id', actor_id)
        )
        on conflict (source_event_key) do nothing;
    end loop;

    return membership_row;
end;
$$;

grant execute on function public.accept_family_invite(text) to authenticated;
