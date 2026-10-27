-- Local-only manual reconciliation history/currency characterizations.
-- Local-only compared-batch fixtures. No production data or connection.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'authenticated','authenticated',email,'',now(),'{"provider":"email","providers":["email"]}','{}',now(),now()
from (values ('59000000-0000-4000-8000-000000000001'::uuid,'cash-batch-a@mistia.test'),('59000000-0000-4000-8000-000000000002'::uuid,'cash-batch-b@mistia.test')) f(id,email);
insert into public.user_profiles(user_id,display_name) select id,'Cash scope fixture' from auth.users where id in ('59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000002') on conflict(user_id) do nothing;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('59000000-0000-4000-8000-000000000101','59000000-0000-4000-8000-000000000001','A cash','cash','banknote.fill','#111111','VND',10000),
('59000000-0000-4000-8000-000000000102','59000000-0000-4000-8000-000000000002','B cash','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values ('59000000-0000-4000-8000-000000000201','59000000-0000-4000-8000-000000000001','expense','posted','A expense',100,'2026-10-27T00:00:00Z','59000000-0000-4000-8000-000000000101','VND','VND',100,'59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000001'),
('59000000-0000-4000-8000-000000000202','59000000-0000-4000-8000-000000000002','expense','posted','B expense',100,'2026-10-27T00:00:00Z','59000000-0000-4000-8000-000000000102','VND','VND',100,'59000000-0000-4000-8000-000000000002','59000000-0000-4000-8000-000000000002');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at,sync_version)
values ('59000000-0000-4000-8000-000000000302','59000000-0000-4000-8000-000000000002','59000000-0000-4000-8000-000000000402','59000000-0000-4000-8000-000000000102','59000000-0000-4000-8000-000000000202','cashCorrection','booked','manual',50,'VND',50,'VND','2026-10-27T00:00:00Z',7);
select set_config('request.jwt.claim.sub','59000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
create function pg_temp.posting(p_id uuid,p_amount bigint default 20) returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','59000000-0000-4000-8000-000000000001','event_id','59000000-0000-4000-8000-000000000401','wallet_id','59000000-0000-4000-8000-000000000101','ledger_transaction_id','59000000-0000-4000-8000-000000000201','role_raw_value','cashCorrection','cash_bucket_raw_value','booked','cash_origin_raw_value','manual','amount_minor',p_amount,'accounting_amount_minor',p_amount,'currency_code','VND','accounting_currency_code','VND','occurred_at','2026-10-27T00:00:00Z','created_at','2026-10-27T00:00:00Z','updated_at','2026-10-27T00:00:00Z','deleted_at',null,'last_modified_by_device_id','59000000-0000-4000-8000-000000000901')
$$;

insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('59000000-0000-4000-8000-000000000103','59000000-0000-4000-8000-000000000001','Linked','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,system_purpose_raw_value,investment_linked_wallet_id)
values (public.investment_system_wallet_id('59000000-0000-4000-8000-000000000001'),'59000000-0000-4000-8000-000000000001','Investment','investment','chart.line.uptrend.xyaxis','#9A67FF','VND',0,'investmentProfit','59000000-0000-4000-8000-000000000103');
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,transfer_subtype_raw_value,entry_status_raw_value,title,amount_minor,destination_amount_minor,occurred_at,source_wallet_id,destination_wallet_id,source_currency_code,destination_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id,settlement_role_raw_value)
values ('59000000-0000-4000-8000-000000000203','59000000-0000-4000-8000-000000000001','transfer','internalTransfer','posted','Reconciliation',30,30,'2026-10-27T00:00:00Z','59000000-0000-4000-8000-000000000101','59000000-0000-4000-8000-000000000103','VND','VND','VND',30,'59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000001','investmentCashReconciliation');
create function pg_temp.reconciliation(p_id uuid,p_wallet uuid,p_amount bigint,p_event uuid default '59000000-0000-4000-8000-000000000601') returns jsonb language sql as $$
select pg_temp.posting(p_id,p_amount)||jsonb_build_object('event_id',p_event,'wallet_id',p_wallet,'ledger_transaction_id','59000000-0000-4000-8000-000000000203','role_raw_value','cashReconciliation')
$$;

insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('59000000-0000-4000-8000-000000000104','59000000-0000-4000-8000-000000000001','New linked','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,transfer_subtype_raw_value,entry_status_raw_value,title,amount_minor,destination_amount_minor,occurred_at,source_wallet_id,destination_wallet_id,source_currency_code,destination_currency_code,reporting_currency_code,reporting_amount_minor,reporting_income_minor,reporting_expense_minor,created_by_user_id,last_modified_by_user_id,settlement_role_raw_value)
values (public.investment_ledger_id('59000000-0000-4000-8000-000000000610','cash-reconciliation'),'59000000-0000-4000-8000-000000000001','transfer','internalTransfer','posted','Confirmed real80 profit50',80,80,'2026-10-27T00:00:00Z','59000000-0000-4000-8000-000000000101','59000000-0000-4000-8000-000000000103','VND','VND','VND',80,0,0,'59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000001','investmentReconciliation');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at)
select '59000000-0000-4000-8000-000000000321','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000421','59000000-0000-4000-8000-000000000101','59000000-0000-4000-8000-000000000201','cashAccrual','booked','derived',100,'VND',100,'VND','2026-10-27T00:00:00Z';
create function pg_temp.canonical_rows() returns jsonb language sql as $$
select jsonb_build_array(
 pg_temp.posting(public.investment_ledger_id('59000000-0000-4000-8000-000000000610','holder-cash-posting'),-50)||jsonb_build_object('event_id','59000000-0000-4000-8000-000000000610','ledger_transaction_id',public.investment_ledger_id('59000000-0000-4000-8000-000000000610','cash-reconciliation'),'role_raw_value','cashReconciliation'),
 pg_temp.posting(public.investment_ledger_id('59000000-0000-4000-8000-000000000610','linked-cash-posting'),50)||jsonb_build_object('event_id','59000000-0000-4000-8000-000000000610','ledger_transaction_id',public.investment_ledger_id('59000000-0000-4000-8000-000000000610','cash-reconciliation'),'wallet_id','59000000-0000-4000-8000-000000000103','role_raw_value','cashReconciliation'))
$$;
create function pg_temp.expected(p_rows jsonb) returns jsonb language sql as $$
select jsonb_object_agg(value->>'id',coalesce((select sync_version from public.investment_wallet_postings p where p.id=(value->>'id')::uuid),0)) from jsonb_array_elements(p_rows)
$$;
create function pg_temp.publish(p_rows jsonb default pg_temp.canonical_rows()) returns void language sql as $$
select public.mutate_investment_cash_postings(p_rows,pg_temp.expected(p_rows),false)
$$;
-- A link selection made after the real confirmed transfer must not redirect its history.
update public.ledger_wallets set investment_linked_wallet_id='59000000-0000-4000-8000-000000000104' where id=public.investment_system_wallet_id('59000000-0000-4000-8000-000000000001');
select lives_ok('select pg_temp.publish()','confirmed historical destination remains publishable after changing the linked wallet');
select is((select count(*) from public.investment_wallet_postings where event_id='59000000-0000-4000-8000-000000000610'),2::bigint,'both canonical postings publish atomically');
select is((select array_agg(accounting_amount_minor order by accounting_amount_minor)::text from public.investment_wallet_postings where event_id='59000000-0000-4000-8000-000000000610'),'{-50,50}','real80 keeps only booked50, without redirecting allocation');
select is((select amount_minor from public.ledger_transactions where id=public.investment_ledger_id('59000000-0000-4000-8000-000000000610','cash-reconciliation')),80::bigint,'real ledger amount remains80');
update public.ledger_wallets set investment_linked_wallet_id=null where id=public.investment_system_wallet_id('59000000-0000-4000-8000-000000000001');
select lives_ok('select pg_temp.publish()','clearing the current link does not erase confirmed transfer ancestry');
select is((select min(sync_version) from public.investment_wallet_postings where event_id='59000000-0000-4000-8000-000000000610'),2::bigint,'compared existing pair advances once without creating another real transfer');
update public.ledger_wallets set investment_linked_wallet_id='59000000-0000-4000-8000-000000000103' where id=public.investment_system_wallet_id('59000000-0000-4000-8000-000000000001');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{1,wallet_id}','"59000000-0000-4000-8000-000000000104"')),'P0001',null,'current new link cannot replace historical destination');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{0,currency_code}','"JPY"')),'P0001',null,'mixed local currency is rejected before writing either posting');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{1,accounting_currency_code}','"JPY"')),'P0001',null,'mixed accounting currency cannot reinterpret minor units');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{1,amount_minor}','49')),'P0001',null,'local amount must equal exact accounting amount');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{0,ledger_transaction_id}','"59000000-0000-4000-8000-000000000201"')),'P0001',null,'both postings must reference the same canonical transfer');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{0,id}','"59000000-0000-4000-8000-000000000399"')),'P0001',null,'a noncanonical posting identity cannot inherit historical authority');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.canonical_rows(),'{0,trade_id}','"59000000-0000-4000-8000-000000000777"')),'P0001',null,'manual reconciliation cannot annex a trade');
update public.ledger_transactions set amount_minor=40,destination_amount_minor=40,reporting_amount_minor=40 where id=public.investment_ledger_id('59000000-0000-4000-8000-000000000610','cash-reconciliation');
select throws_ok('select pg_temp.publish()','P0001',null,'booked profit cannot exceed the confirmed real transfer');
update public.ledger_transactions set amount_minor=80,destination_amount_minor=80,reporting_amount_minor=80,settlement_role_raw_value='investmentCashReconciliation' where id=public.investment_ledger_id('59000000-0000-4000-8000-000000000610','cash-reconciliation');
select throws_ok('select pg_temp.publish()','P0001',null,'wrong historical ledger role cannot authorize manual reconciliation');
select is((select min(sync_version) from public.investment_wallet_postings where event_id='59000000-0000-4000-8000-000000000610'),2::bigint,'all invalid attempts retain original compared versions');
select is((select count(*) from public.investment_wallet_postings where id='59000000-0000-4000-8000-000000000399'),0::bigint,'invalid identity was never inserted');

-- A historical pair still uses the immutable accounting currency of the root.
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('59000000-0000-4000-8000-000000000105','59000000-0000-4000-8000-000000000001','JPY holder','cash','banknote.fill','#111111','JPY',10000),
('59000000-0000-4000-8000-000000000106','59000000-0000-4000-8000-000000000001','JPY destination','cash','banknote.fill','#111111','JPY',0);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,transfer_subtype_raw_value,entry_status_raw_value,title,amount_minor,destination_amount_minor,occurred_at,source_wallet_id,destination_wallet_id,source_currency_code,destination_currency_code,reporting_currency_code,reporting_amount_minor,reporting_income_minor,reporting_expense_minor,created_by_user_id,last_modified_by_user_id,settlement_role_raw_value)
values (public.investment_ledger_id('59000000-0000-4000-8000-000000000620','cash-reconciliation'),'59000000-0000-4000-8000-000000000001','transfer','internalTransfer','posted','Wrong root currency',80,80,'2026-10-27T00:00:00Z','59000000-0000-4000-8000-000000000105','59000000-0000-4000-8000-000000000106','JPY','JPY','JPY',80,0,0,'59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000001','investmentReconciliation');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at)
values ('59000000-0000-4000-8000-000000000322','59000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000422','59000000-0000-4000-8000-000000000105',public.investment_ledger_id('59000000-0000-4000-8000-000000000620','cash-reconciliation'),'cashAccrual','booked','derived',100,'JPY',100,'JPY','2026-10-27T00:00:00Z');
create function pg_temp.foreign_accounting_rows() returns jsonb language sql as $$
select jsonb_build_array(
 pg_temp.posting(public.investment_ledger_id('59000000-0000-4000-8000-000000000620','holder-cash-posting'),-50)||jsonb_build_object('event_id','59000000-0000-4000-8000-000000000620','ledger_transaction_id',public.investment_ledger_id('59000000-0000-4000-8000-000000000620','cash-reconciliation'),'role_raw_value','cashReconciliation','wallet_id','59000000-0000-4000-8000-000000000105','currency_code','JPY','accounting_currency_code','JPY'),
 pg_temp.posting(public.investment_ledger_id('59000000-0000-4000-8000-000000000620','linked-cash-posting'),50)||jsonb_build_object('event_id','59000000-0000-4000-8000-000000000620','ledger_transaction_id',public.investment_ledger_id('59000000-0000-4000-8000-000000000620','cash-reconciliation'),'role_raw_value','cashReconciliation','wallet_id','59000000-0000-4000-8000-000000000106','currency_code','JPY','accounting_currency_code','JPY'))
$$;
select throws_ok('select pg_temp.publish(pg_temp.foreign_accounting_rows())','P0001','investment_cash_invalid_confirmed_reconciliation','historical authority cannot bypass the immutable root accounting currency');
select is((select count(*) from public.investment_wallet_postings where event_id='59000000-0000-4000-8000-000000000620'),0::bigint,'wrong-root currency rejection creates neither posting');

select * from finish();
rollback;
