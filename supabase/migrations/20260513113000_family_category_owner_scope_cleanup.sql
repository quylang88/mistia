-- Move post-deploy category ownership changes into a forward migration.
-- Family transaction request flow is no longer used: family wallets must
-- always save directly with a category that already exists on the owner's cloud.

drop function if exists public.respond_family_transaction_request(uuid, boolean);
drop function if exists public.create_family_transaction_request(uuid, uuid, jsonb, jsonb, text, text);
drop function if exists public.resolve_family_transaction_request_category(uuid, jsonb);
drop table if exists public.family_transaction_requests;

create or replace function public.transaction_category_matches_owner(target_category_id uuid, owner_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        target_category_id is null
        or exists (
            select 1
            from public.transaction_categories c
            where c.id = target_category_id
              and c.user_id = owner_user_id
              and c.deleted_at is null
        );
$$;

drop policy if exists "categories_family_member_select" on public.transaction_categories;
drop policy if exists "categories_family_access_select" on public.transaction_categories;
create policy "categories_family_access_select"
on public.transaction_categories
for select
to authenticated
using (public.has_family_finance_view_access(user_id, false));
