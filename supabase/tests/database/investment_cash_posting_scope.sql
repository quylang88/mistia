-- Synthetic local-only owner/CAS boundary fixtures. No production connection or data.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'authenticated','authenticated',email,'',now(),'{"provider":"email","providers":["email"]}','{}',now(),now()
from (values ('57000000-0000-4000-8000-000000000001'::uuid,'cash-scope-a@mistia.test'),('57000000-0000-4000-8000-000000000002'::uuid,'cash-scope-b@mistia.test')) f(id,email);
insert into public.user_profiles(user_id,display_name) select id,'Cash scope fixture' from auth.users where id in ('57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000002') on conflict(user_id) do nothing;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('57000000-0000-4000-8000-000000000101','57000000-0000-4000-8000-000000000001','A cash','cash','banknote.fill','#111111','VND',10000),
('57000000-0000-4000-8000-000000000102','57000000-0000-4000-8000-000000000002','B cash','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values ('57000000-0000-4000-8000-000000000201','57000000-0000-4000-8000-000000000001','expense','posted','A expense',100,'2026-10-27T00:00:00Z','57000000-0000-4000-8000-000000000101','VND','VND',100,'57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000001'),
('57000000-0000-4000-8000-000000000202','57000000-0000-4000-8000-000000000002','expense','posted','B expense',100,'2026-10-27T00:00:00Z','57000000-0000-4000-8000-000000000102','VND','VND',100,'57000000-0000-4000-8000-000000000002','57000000-0000-4000-8000-000000000002');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at,sync_version)
values ('57000000-0000-4000-8000-000000000302','57000000-0000-4000-8000-000000000002','57000000-0000-4000-8000-000000000402','57000000-0000-4000-8000-000000000102','57000000-0000-4000-8000-000000000202','cashCorrection','booked','manual',50,'VND',50,'VND','2026-10-27T00:00:00Z',7);
select set_config('request.jwt.claim.sub','57000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
create function pg_temp.posting(p_id uuid,p_amount bigint default 20) returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','57000000-0000-4000-8000-000000000001','event_id','57000000-0000-4000-8000-000000000401','wallet_id','57000000-0000-4000-8000-000000000101','ledger_transaction_id','57000000-0000-4000-8000-000000000201','role_raw_value','cashCorrection','cash_bucket_raw_value','booked','cash_origin_raw_value','manual','amount_minor',p_amount,'accounting_amount_minor',p_amount,'currency_code','VND','accounting_currency_code','VND','occurred_at','2026-10-27T00:00:00Z','created_at','2026-10-27T00:00:00Z','updated_at','2026-10-27T00:00:00Z','deleted_at',null,'last_modified_by_device_id','57000000-0000-4000-8000-000000000901')
$$;
select is((public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301'),0,false)).sync_version,1::bigint,'owned base-zero creation remains supported');
select is((public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301',30),1,false)).sync_version,2::bigint,'owned compared update remains supported');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000302',99),7,false)$$,'P0001','Invalid investment cash posting','known foreign ID cannot redirect another owner allocation');
select is((select accounting_amount_minor from public.investment_wallet_postings where id='57000000-0000-4000-8000-000000000302'),50::bigint,'foreign allocation business remains intact');
select is((select wallet_id from public.investment_wallet_postings where id='57000000-0000-4000-8000-000000000302'),'57000000-0000-4000-8000-000000000102'::uuid,'foreign allocation cannot be moved into caller wallet');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000303'),9,false)$$,'P0001','version_conflict','missing positive-base allocation cannot be recreated');
select is((select count(*) from public.investment_wallet_postings where id='57000000-0000-4000-8000-000000000303'),0::bigint,'comparison failure leaves no inserted identity');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000302',111),7,true)$$,'P0001','Invalid investment cash posting','force does not bypass existing owner identity');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000302')||jsonb_build_object('deleted_at','2026-10-27T01:00:00Z'),7,true)$$,'P0001','Invalid investment cash posting','force cannot retire another owner posting');
select ok((select deleted_at is null from public.investment_wallet_postings where id='57000000-0000-4000-8000-000000000302'),'foreign active state remains intact');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301'),1,false)$$,'P0001','version_conflict','stale owned version remains rejected');
select is((public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301'),null,false)).sync_version,3::bigint,'valid legacy nil-version same-owner update remains supported');
select is((public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301'),0,true)).sync_version,4::bigint,'same-owner force retains its existing conflict-resolution semantics');
select is((public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000305'),null,false)).sync_version,1::bigint,'legacy nil-version creation remains supported');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301'),0,false)$$,'P0001','version_conflict','base zero cannot overwrite an existing owned posting');
select is((public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000304'),9,true)).sync_version,1::bigint,'same-owner explicit force preserves legacy absent-row behavior');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000301'),0,null)$$,'P0001','version_conflict','null force is not explicit permission to bypass a stale comparison');
select throws_ok($$select public.mutate_investment_cash_posting(pg_temp.posting('57000000-0000-4000-8000-000000000306'),9,null)$$,'P0001','version_conflict','null force cannot recreate an absent positive-base update');
select * from finish();
rollback;
