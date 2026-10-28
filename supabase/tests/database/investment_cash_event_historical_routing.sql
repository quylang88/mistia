begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

-- Synthetic local owner and imported legacy profit. This tests the real cash RPC, not FIFO rebuild.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('57000000-0000-4000-8000-000000000001','authenticated','authenticated','historical-cash@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('57000000-0000-4000-8000-000000000001','Historical cash fixture') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','57000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('57000000-0000-4000-8000-000000000101','57000000-0000-4000-8000-000000000001','Linked','cash','banknote.fill','#111111','VND',10000),
('57000000-0000-4000-8000-000000000102','57000000-0000-4000-8000-000000000001','Selected','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,system_purpose_raw_value,investment_linked_wallet_id)
values (public.investment_system_wallet_id('57000000-0000-4000-8000-000000000001'),'57000000-0000-4000-8000-000000000001','Investment','investment','chart.line.uptrend.xyaxis','#9A67FF','VND',0,'investmentProfit','57000000-0000-4000-8000-000000000101');
insert into public.investment_channels(id,user_id,name) values ('57000000-0000-4000-8000-000000000201','57000000-0000-4000-8000-000000000001','Legacy channel');
insert into public.investment_assets(id,user_id,channel_id,name,currency_code) values ('57000000-0000-4000-8000-000000000301','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000201','Legacy asset','VND');
insert into public.investment_trades(id,user_id,channel_id,asset_id,kind_raw_value,quantity_decimal_string,gross_amount_minor,currency_code,accounting_gross_amount_minor,accounting_currency_code,realized_profit_loss_minor,capital_return_wallet_id,occurred_at)
values ('57000000-0000-4000-8000-000000000401','57000000-0000-4000-8000-000000000001','57000000-0000-4000-8000-000000000201','57000000-0000-4000-8000-000000000301','sell','1',800,'VND',800,'VND',800,'57000000-0000-4000-8000-000000000102','2026-10-26T00:00:00Z');
create function pg_temp.cash_proposal(p_id uuid,p_amount bigint default 50) returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','57000000-0000-4000-8000-000000000001','primary_kind_raw_value','transfer','transfer_subtype_raw_value','internalTransfer',
'entry_status_raw_value','posted','title','Cash event','note',null,'amount_minor',p_amount,'destination_amount_minor',p_amount,'reporting_amount_minor',p_amount,
'source_currency_code','VND','destination_currency_code','VND','reporting_currency_code','VND','reporting_expense_minor',0,'reporting_income_minor',0,
'settlement_role_raw_value','investmentCashDeposit','source_wallet_id','57000000-0000-4000-8000-000000000102','destination_wallet_id','57000000-0000-4000-8000-000000000101',
'created_at','2026-10-27T00:00:00Z','occurred_at','2026-10-27T00:01:00Z','updated_at','2026-10-27T00:05:00Z','is_archived',false,
'last_modified_by_device_id','57000000-0000-4000-8000-000000000901')
$$;

-- The default changes after the event's endpoints have been confirmed offline.
update public.ledger_wallets set investment_linked_wallet_id='57000000-0000-4000-8000-000000000102'
where id=public.investment_system_wallet_id('57000000-0000-4000-8000-000000000001');
select lives_ok($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000501'),'[]',0,'{}',false)$$,
'confirmed deposit can publish to its captured wallet after a later default choice');
select is((select count(*) from public.ledger_transactions where id='57000000-0000-4000-8000-000000000501'),1::bigint,'historical deposit has one real ledger');
select is((select destination_wallet_id from public.ledger_transactions where id='57000000-0000-4000-8000-000000000501'),'57000000-0000-4000-8000-000000000101'::uuid,'later preference does not redirect deposit destination');
select is((select wallet_id from public.investment_wallet_postings where event_id='57000000-0000-4000-8000-000000000501'),'57000000-0000-4000-8000-000000000101'::uuid,'canonical allocation follows captured deposit endpoint');
create function pg_temp.withdrawal(p_amount bigint default 20) returns jsonb language sql as $$
select pg_temp.cash_proposal('57000000-0000-4000-8000-000000000502',p_amount) || jsonb_build_object(
'settlement_role_raw_value','investmentCashWithdrawal','source_wallet_id','57000000-0000-4000-8000-000000000101','destination_wallet_id','57000000-0000-4000-8000-000000000102')
$$;
select lives_ok($$select * from public.mutate_investment_cash_event(pg_temp.withdrawal(),'[]',0,'{}',false)$$,'confirmed withdrawal uses original wallet booked capacity after later default');
select is((select source_wallet_id from public.ledger_transactions where id='57000000-0000-4000-8000-000000000502'),'57000000-0000-4000-8000-000000000101'::uuid,'later preference does not redirect withdrawal source');
select is((select accounting_amount_minor from public.investment_wallet_postings where event_id='57000000-0000-4000-8000-000000000502'),-20::bigint,'withdrawal allocation retains exact negative amount');
select lives_ok($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000501',40),'[]',1,jsonb_build_object(public.investment_ledger_id('57000000-0000-4000-8000-000000000501','cash-transfer-posting'),1),false)$$,'already captured deposit edit can publish after default change');
select is((select sync_version from public.ledger_transactions where id='57000000-0000-4000-8000-000000000501'),2::bigint,'historical edit keeps exact ledger CAS');
select is((select accounting_amount_minor from public.investment_wallet_postings where event_id='57000000-0000-4000-8000-000000000501'),40::bigint,'historical edit changes canonical allocation once');
-- A legacy tombstone object cannot relabel a consumed deposit as a withdrawal.
select throws_ok($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000501',40)||jsonb_build_object('settlement_role_raw_value','investmentCashWithdrawal','deleted_at','2026-10-28T00:09:00Z'),'[]',2,jsonb_build_object(public.investment_ledger_id('57000000-0000-4000-8000-000000000501','cash-transfer-posting'),2),false)$$,'P0001','investment_cash_has_dependent_events','deletion capacity uses the stored event direction even for legacy tombstone objects');
select ok((select deleted_at is null from public.ledger_transactions where id='57000000-0000-4000-8000-000000000501'),'relabelled tombstone cannot retire the consumed deposit');
select ok((select deleted_at is null from public.investment_wallet_postings where event_id='57000000-0000-4000-8000-000000000501'),'relabelled tombstone preserves the canonical allocation');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where user_id='57000000-0000-4000-8000-000000000001' and cash_bucket_raw_value='booked' and deleted_at is null),20::bigint,'rejected tombstone cannot create negative booked money');
select throws_ok($$select * from public.mutate_investment_cash_event(pg_temp.withdrawal(41),'[]',1,jsonb_build_object(public.investment_ledger_id('57000000-0000-4000-8000-000000000502','cash-transfer-posting'),1),false)$$,'P0001','investment_cash_limit_conflict','withdrawal capacity is checked on captured holder, not the new default');
select is((select amount_minor from public.ledger_transactions where id='57000000-0000-4000-8000-000000000502'),20::bigint,'capacity failure leaves original real withdrawal intact');
select is((select count(*) from public.mutate_investment_cash_event(pg_temp.withdrawal(10),'[]',99,'{}',false)),0::bigint,'historical event preserves exact ledger comparison');
select lives_ok($$select * from public.mutate_investment_cash_event(null,'[]',1,jsonb_build_object(public.investment_ledger_id('57000000-0000-4000-8000-000000000502','cash-transfer-posting'),1),false,'57000000-0000-4000-8000-000000000502','57000000-0000-4000-8000-000000000001','2026-10-28T00:10:00Z','57000000-0000-4000-8000-000000000901')$$,'historical withdrawal deletion uses the event holder');
select ok((select deleted_at is not null from public.ledger_transactions where id='57000000-0000-4000-8000-000000000502'),'withdrawal deletion returns a real tombstone');
select ok((select deleted_at is not null from public.investment_wallet_postings where event_id='57000000-0000-4000-8000-000000000502'),'withdrawal deletion atomically retires its allocation');
-- Clearing a preference later does not delete either captured event endpoint.
update public.ledger_wallets set investment_linked_wallet_id=null where id=public.investment_system_wallet_id('57000000-0000-4000-8000-000000000001');
select lives_ok($$select * from public.mutate_investment_cash_event(null,'[]',2,jsonb_build_object(public.investment_ledger_id('57000000-0000-4000-8000-000000000501','cash-transfer-posting'),2),false,'57000000-0000-4000-8000-000000000501','57000000-0000-4000-8000-000000000001','2026-10-28T00:11:00Z','57000000-0000-4000-8000-000000000901')$$,'deposit deletion is independent of a later empty default preference');
select ok((select deleted_at is not null from public.ledger_transactions where id='57000000-0000-4000-8000-000000000501'),'deposit deleted with no current default');
select ok((select deleted_at is not null from public.investment_wallet_postings where event_id='57000000-0000-4000-8000-000000000501'),'deposit allocation deleted with no current default');

-- Historical routing still requires an owned eligible wallet of the accounting currency.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('57000000-0000-4000-8000-000000000002','authenticated','authenticated','historical-cash-other@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('57000000-0000-4000-8000-000000000002','Other fixture') on conflict(user_id) do nothing;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('57000000-0000-4000-8000-000000000103','57000000-0000-4000-8000-000000000002','Foreign','cash','banknote.fill','#111111','VND',10000),
('57000000-0000-4000-8000-000000000104','57000000-0000-4000-8000-000000000001','Other currency','cash','banknote.fill','#111111','JPY',10000),
('57000000-0000-4000-8000-000000000105','57000000-0000-4000-8000-000000000001','Retired','cash','banknote.fill','#111111','VND',10000);
update public.ledger_wallets set is_archived=true,archived_at=now() where id='57000000-0000-4000-8000-000000000105';
update public.ledger_wallets set investment_linked_wallet_id='57000000-0000-4000-8000-000000000101' where id=public.investment_system_wallet_id('57000000-0000-4000-8000-000000000001');
select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000507')||jsonb_build_object('destination_wallet_id','57000000-0000-4000-8000-000000000103'),'[]',0,'{}',false)$$,'%investment_cash_invalid_%','foreign captured endpoint remains rejected');
select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000508')||jsonb_build_object('destination_wallet_id','57000000-0000-4000-8000-000000000104'),'[]',0,'{}',false)$$,'%investment_cash_invalid_%','different-currency captured endpoint remains rejected');
select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000509')||jsonb_build_object('destination_wallet_id','57000000-0000-4000-8000-000000000105'),'[]',0,'{}',false)$$,'%investment_cash_invalid_%','actually retired captured endpoint is never activated');
select is((select count(*) from public.ledger_transactions where id in ('57000000-0000-4000-8000-000000000507','57000000-0000-4000-8000-000000000508','57000000-0000-4000-8000-000000000509')),0::bigint,'rejected endpoint proposals create no real ledger');
select is((select count(*) from public.investment_wallet_postings where event_id in ('57000000-0000-4000-8000-000000000507','57000000-0000-4000-8000-000000000508','57000000-0000-4000-8000-000000000509')),0::bigint,'rejected endpoint proposals create no allocation');

-- IDs are globally unique: an owner-scoped absent read cannot authorize changing another owner's existing row.
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values ('57000000-0000-4000-8000-000000000510','57000000-0000-4000-8000-000000000002','expense','posted','Foreign real transaction',75,'2026-10-27T00:00:00Z','57000000-0000-4000-8000-000000000103','VND','VND',75,'57000000-0000-4000-8000-000000000002','57000000-0000-4000-8000-000000000002');
select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000510'),'[]',0,'{}',false)$$,'%investment_cash_%','foreign existing real ledger identity cannot be repurposed as caller cash');
select is((select amount_minor from public.ledger_transactions where id='57000000-0000-4000-8000-000000000510'),75::bigint,'foreign ledger money remains intact');
select is((select source_wallet_id from public.ledger_transactions where id='57000000-0000-4000-8000-000000000510'),'57000000-0000-4000-8000-000000000103'::uuid,'foreign ledger source remains intact');
select is((select count(*) from public.investment_wallet_postings where user_id='57000000-0000-4000-8000-000000000001' and event_id='57000000-0000-4000-8000-000000000510'),0::bigint,'foreign ledger collision creates no caller allocation');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at,sync_version)
values (public.investment_ledger_id('57000000-0000-4000-8000-000000000511','cash-transfer-posting'),'57000000-0000-4000-8000-000000000002','57000000-0000-4000-8000-000000000512','57000000-0000-4000-8000-000000000103','57000000-0000-4000-8000-000000000510','cashCorrection','booked','manual',25,'VND',25,'VND','2026-10-27T00:00:00Z',7);
select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000511'),'[]',0,'{}',false)$$,'%investment_cash_%','foreign canonical allocation identity cannot be overwritten by a cash event');
select is((select accounting_amount_minor from public.investment_wallet_postings where id=public.investment_ledger_id('57000000-0000-4000-8000-000000000511','cash-transfer-posting')),25::bigint,'foreign canonical money remains intact');
select is((select wallet_id from public.investment_wallet_postings where id=public.investment_ledger_id('57000000-0000-4000-8000-000000000511','cash-transfer-posting')),'57000000-0000-4000-8000-000000000103'::uuid,'foreign canonical wallet remains intact');
select is((select ledger_transaction_id from public.investment_wallet_postings where id=public.investment_ledger_id('57000000-0000-4000-8000-000000000511','cash-transfer-posting')),'57000000-0000-4000-8000-000000000510'::uuid,'foreign canonical event reference remains intact');
select is((select count(*) from public.ledger_transactions where id='57000000-0000-4000-8000-000000000511'),0::bigint,'foreign allocation collision rolls back caller real ledger');

select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000510'),'[]',null,'{}',true)$$,'%investment_cash_%','force cannot bypass foreign ledger ownership');
select throws_like($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000511'),'[]',null,'{}',true)$$,'%investment_cash_%','force cannot bypass foreign canonical allocation ownership');
select is((select sync_version from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000513'),'[]',999,'{}',true)),1::bigint,'valid same-owner legacy force creation remains supported');
select is((select sync_version from public.mutate_investment_cash_event(pg_temp.cash_proposal('57000000-0000-4000-8000-000000000513',40),'[]',999,'{}',true)),2::bigint,'valid same-owner legacy force update remains supported');
select * from finish();
rollback;
