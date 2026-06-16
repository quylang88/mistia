-- System categories are now first-class cloud data.
-- The previous upload guard only allowed active system-category rows when they
-- already had a cloud dependency or when the client created a temporary
-- allowance. That blocks the new all-category cloud bootstrap path.

drop trigger if exists guard_system_category_uploads on public.transaction_categories;

drop function if exists public.guard_system_category_upload();
drop function if exists public.allow_system_category_upload(uuid, uuid);
drop function if exists public.system_category_has_cloud_dependency(uuid, uuid);

drop table if exists public.system_category_upload_allowances;

notify pgrst, 'reload schema';
