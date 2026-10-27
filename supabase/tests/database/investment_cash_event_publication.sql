begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

-- Synthetic local owner and imported legacy profit. This tests the real cash RPC, not FIFO rebuild.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('56000000-0000-4000-8000-000000000001','authenticated','authenticated','cash-publication@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('56000000-0000-4000-8000-000000000001','Cash publication fixture') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','56000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('56000000-0000-4000-8000-000000000101','56000000-0000-4000-8000-000000000001','Linked','cash','banknote.fill','#111111','VND',10000),
('56000000-0000-4000-8000-000000000102','56000000-0000-4000-8000-000000000001','Selected','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,system_purpose_raw_value,investment_linked_wallet_id)
values (public.investment_system_wallet_id('56000000-0000-4000-8000-000000000001'),'56000000-0000-4000-8000-000000000001','Investment','investment','chart.line.uptrend.xyaxis','#9A67FF','VND',0,'investmentProfit','56000000-0000-4000-8000-000000000101');
insert into public.investment_channels(id,user_id,name) values ('56000000-0000-4000-8000-000000000201','56000000-0000-4000-8000-000000000001','Legacy channel');
insert into public.investment_assets(id,user_id,channel_id,name,currency_code) values ('56000000-0000-4000-8000-000000000301','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000201','Legacy asset','VND');
insert into public.investment_trades(id,user_id,channel_id,asset_id,kind_raw_value,quantity_decimal_string,gross_amount_minor,currency_code,accounting_gross_amount_minor,accounting_currency_code,realized_profit_loss_minor,capital_return_wallet_id,occurred_at)
values ('56000000-0000-4000-8000-000000000401','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000201','56000000-0000-4000-8000-000000000301','sell','1',800,'VND',800,'VND',800,'56000000-0000-4000-8000-000000000102','2026-10-26T00:00:00Z');
create function pg_temp.cash_proposal(p_id uuid,p_amount bigint default 50) returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','56000000-0000-4000-8000-000000000001','primary_kind_raw_value','transfer','transfer_subtype_raw_value','internalTransfer',
'entry_status_raw_value','posted','title','Cash event','note',null,'amount_minor',p_amount,'destination_amount_minor',p_amount,'reporting_amount_minor',p_amount,
'source_currency_code','VND','destination_currency_code','VND','reporting_currency_code','VND','reporting_expense_minor',0,'reporting_income_minor',0,
'settlement_role_raw_value','investmentCashDeposit','source_wallet_id','56000000-0000-4000-8000-000000000102','destination_wallet_id','56000000-0000-4000-8000-000000000101',
'created_at','2026-10-27T00:00:00Z','occurred_at','2026-10-27T00:01:00Z','updated_at','2026-10-27T00:05:00Z','is_archived',false,
'last_modified_by_device_id','56000000-0000-4000-8000-000000000901')
$$;
create temporary table reply on commit drop as select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('56000000-0000-4000-8000-000000000501'), '[]',0,'{}',false);
select is((select count(*) from reply),1::bigint,'cash RPC returns exactly the requested ledger');
select is((select sync_version from reply),1::bigint,'cash ledger advances exactly once');
select is((select created_by_user_id from reply),'56000000-0000-4000-8000-000000000001'::uuid,'SQL stamps authenticated creator');
select is((select accounting_amount_minor from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000501'),50::bigint,'SQL creates the positive canonical booked allocation');
select is((select id from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000501'),public.investment_ledger_id('56000000-0000-4000-8000-000000000501','cash-transfer-posting'),'cash posting identity is deterministic');
select is((select created_at from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000501'),'2026-10-27T00:00:00Z'::timestamptz,'new posting uses ledger creation time rather than save time');
select is((select count(*) from public.mutate_investment_cash_event(pg_temp.cash_proposal('56000000-0000-4000-8000-000000000501',40),'[]',0,'{}',false)),0::bigint,'ledger CAS mismatch returns no rows');
select is((select count(*) from public.mutate_investment_cash_event(pg_temp.cash_proposal('56000000-0000-4000-8000-000000000501',40),'[]',1,jsonb_build_object(public.investment_ledger_id('56000000-0000-4000-8000-000000000501','cash-transfer-posting'),99),false)),0::bigint,'canonical posting CAS mismatch returns no rows');
select is((select amount_minor from public.ledger_transactions where id='56000000-0000-4000-8000-000000000501'),50::bigint,'both CAS misses preserve original business intent');
truncate reply;
insert into reply select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('56000000-0000-4000-8000-000000000501',40),'[]',1,jsonb_build_object(public.investment_ledger_id('56000000-0000-4000-8000-000000000501','cash-transfer-posting'),1),false);
select is((select sync_version from reply),2::bigint,'successful update advances ledger once');
select is((select sync_version from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000501'),2::bigint,'successful update advances canonical posting once');
select is((select created_at from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000501'),'2026-10-27T00:00:00Z'::timestamptz,'update retains immutable posting creation time');
select throws_ok($$select * from public.mutate_investment_cash_event(pg_temp.cash_proposal('56000000-0000-4000-8000-000000000502',801),'[]',0,'{}',false)$$,'P0001','investment_cash_limit_conflict','capacity rejection has the exact retryable SQL condition');
select is((select count(*) from public.ledger_transactions where id='56000000-0000-4000-8000-000000000502'),0::bigint,'capacity failure leaves no partial ledger');
select is((select count(*) from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000502'),0::bigint,'capacity failure leaves no partial posting');
-- Retained zero-value sibling is valid event state; DELETE must retire every active event posting.
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,cash_bucket_raw_value,cash_origin_raw_value,occurred_at)
values ('56000000-0000-4000-8000-000000000601','56000000-0000-4000-8000-000000000001','56000000-0000-4000-8000-000000000501','56000000-0000-4000-8000-000000000101','56000000-0000-4000-8000-000000000501','cashCorrection',0,'VND',0,'VND','booked','manual','2026-10-27T00:00:00Z');
truncate reply;
insert into reply select * from public.mutate_investment_cash_event(null,'[]',2,jsonb_build_object(public.investment_ledger_id('56000000-0000-4000-8000-000000000501','cash-transfer-posting'),2),false,'56000000-0000-4000-8000-000000000501','56000000-0000-4000-8000-000000000001','2026-10-27T00:07:00Z','56000000-0000-4000-8000-000000000901');
select is((select sync_version from reply),3::bigint,'delete returns the requested next-version ledger only');
select ok((select deleted_at is not null from reply),'delete returns a real ledger tombstone');
select is((select count(*) from public.investment_wallet_postings where event_id='56000000-0000-4000-8000-000000000501' and deleted_at is not null),2::bigint,'delete tombstones canonical and retained sibling atomically');
select is((select count(*) from public.mutate_investment_cash_event(null,'[]',3,'{}',false,'56000000-0000-4000-8000-000000000501','56000000-0000-4000-8000-000000000001','2026-10-27T00:08:00Z','56000000-0000-4000-8000-000000000901')),0::bigint,'already-deleted event returns an empty reply');
select * from finish();
rollback;
