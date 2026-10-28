-- Synthetic local-only linked-wallet-move characterizations; all fixtures roll back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('61000000-0000-4000-8000-000000000001','authenticated','authenticated','linked-move@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('61000000-0000-4000-8000-000000000001','Linked move fixture') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
select ('61000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'61000000-0000-4000-8000-000000000001','Cash'||n,'cash','banknote.fill','#111111',case when n in (105,106) then 'JPY' else 'VND' end,10000
from generate_series(101,106)n;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,system_purpose_raw_value,investment_linked_wallet_id)
values(public.investment_system_wallet_id('61000000-0000-4000-8000-000000000001'),'61000000-0000-4000-8000-000000000001','Investment','investment','chart.line.uptrend.xyaxis','#9A67FF','VND',0,'investmentProfit','61000000-0000-4000-8000-000000000103');
create function pg_temp.ledger(p_event uuid,p_source uuid default '61000000-0000-4000-8000-000000000101',p_destination uuid default '61000000-0000-4000-8000-000000000102',p_currency text default 'VND') returns void language sql as $$
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,transfer_subtype_raw_value,entry_status_raw_value,title,amount_minor,destination_amount_minor,occurred_at,source_wallet_id,destination_wallet_id,source_currency_code,destination_currency_code,reporting_currency_code,reporting_amount_minor,reporting_income_minor,reporting_expense_minor,created_by_user_id,last_modified_by_user_id,settlement_role_raw_value)
values(public.investment_ledger_id(p_event,'linked-wallet-move'),'61000000-0000-4000-8000-000000000001','transfer','internalTransfer','posted','Confirmed linked move',50,50,'2026-10-28T00:00:00Z',p_source,p_destination,p_currency,p_currency,p_currency,50,0,0,'61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','investmentReconciliation')
$$;
select pg_temp.ledger('61000000-0000-4000-8000-000000000501');
select pg_temp.ledger('61000000-0000-4000-8000-000000000502','61000000-0000-4000-8000-000000000105','61000000-0000-4000-8000-000000000106','JPY');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at)
select ('61000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'61000000-0000-4000-8000-000000000001',case when n=305 then '61000000-0000-4000-8000-000000000602'::uuid else '61000000-0000-4000-8000-000000000601'::uuid end,('61000000-0000-4000-8000-'||lpad((n-200)::text,12,'0'))::uuid,public.investment_ledger_id(case when n=305 then '61000000-0000-4000-8000-000000000502'::uuid else '61000000-0000-4000-8000-000000000501'::uuid end,'linked-wallet-move'),'cashAccrual','booked','derived',100,case when n=305 then 'JPY' else 'VND' end,100,case when n=305 then 'JPY' else 'VND' end,'2026-10-28T00:00:00Z'
from (values(301),(305)) f(n);
create function pg_temp.rows(p_event uuid default '61000000-0000-4000-8000-000000000501',p_source uuid default '61000000-0000-4000-8000-000000000101',p_destination uuid default '61000000-0000-4000-8000-000000000102',p_currency text default 'VND') returns jsonb language sql as $$
select jsonb_agg(jsonb_build_object('id',public.investment_ledger_id(p_event,case when n=0 then 'old-linked-cash-posting' else 'new-linked-cash-posting' end),'user_id','61000000-0000-4000-8000-000000000001','event_id',p_event,'wallet_id',case when n=0 then p_source else p_destination end,'ledger_transaction_id',public.investment_ledger_id(p_event,'linked-wallet-move'),'trade_id',null,'asset_id',null,'role_raw_value','cashTransfer','cash_bucket_raw_value','booked','cash_origin_raw_value','manual','amount_minor',case when n=0 then -50 else 50 end,'accounting_amount_minor',case when n=0 then -50 else 50 end,'currency_code',p_currency,'accounting_currency_code',p_currency,'occurred_at','2026-10-28T00:00:00Z','created_at','2026-10-28T00:00:00Z','updated_at','2026-10-28T00:00:00Z','deleted_at',null,'last_modified_by_device_id','61000000-0000-4000-8000-000000000901') order by n) from generate_series(0,1)n
$$;
create function pg_temp.expected(p_rows jsonb) returns jsonb language sql as $$
select jsonb_object_agg(value->>'id',coalesce((select sync_version from public.investment_wallet_postings p where p.id=(value->>'id')::uuid),0)) from jsonb_array_elements(p_rows)
$$;
create function pg_temp.publish(p_rows jsonb default pg_temp.rows()) returns void language sql as $$
select public.mutate_investment_cash_postings(p_rows,pg_temp.expected(p_rows),false)
$$;
select lives_ok('select pg_temp.publish()','historical linked move publishes while current default points elsewhere');
select is((select array_agg(accounting_amount_minor order by accounting_amount_minor)::text from public.investment_wallet_postings where event_id='61000000-0000-4000-8000-000000000501'),'{-50,50}','the complete real amount moves between exactly two cash locations');
select is((select amount_minor from public.ledger_transactions where id=public.investment_ledger_id('61000000-0000-4000-8000-000000000501','linked-wallet-move')),50::bigint,'posting publication does not create or change the real ledger transfer');
select lives_ok('select pg_temp.publish()','known existing pair can be compared and replayed without another transfer');
select is((select min(sync_version) from public.investment_wallet_postings where event_id='61000000-0000-4000-8000-000000000501'),2::bigint,'existing rows each advance exactly one compared version');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_build_array(pg_temp.rows()->0)),'P0001','investment_cash_invalid_linked_move','canonical linked move cannot publish only its source posting');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,amount_minor}','49')),'P0001','investment_cash_invalid_linked_move','local minor amount must equal the exact accounting delta');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,accounting_amount_minor}','49')),'P0001','investment_cash_invalid_linked_move','pair must move the complete real amount');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,wallet_id}','"61000000-0000-4000-8000-000000000103"')),'P0001','investment_cash_invalid_linked_move','a later default cannot redirect the confirmed destination');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{0,currency_code}','"JPY"')),'P0001','investment_cash_invalid_linked_move','local money cannot silently change currency');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,accounting_currency_code}','"JPY"')),'P0001','investment_cash_invalid_linked_move','accounting money cannot silently change currency');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{0,trade_id}','"61000000-0000-4000-8000-000000000701"')),'P0001','investment_cash_invalid_linked_move','manual move cannot annex a trade');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{0,ledger_transaction_id}',to_jsonb(public.investment_ledger_id('61000000-0000-4000-8000-000000000502','linked-wallet-move')::text))),'P0001','investment_cash_invalid_linked_move','both postings must bind the same canonical real transfer');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{0,id}','"61000000-0000-4000-8000-000000000399"')),'P0001','investment_cash_invalid_linked_move','a different posting identity cannot inherit the confirmed move');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,cash_bucket_raw_value}','"unreconciled"')),'P0001','investment_cash_invalid_linked_move','changing buckets cannot create synthetic profit');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,deleted_at}','"2026-10-28T00:01:00Z"')),'P0001','investment_cash_invalid_linked_move','an immutable real move does not permit a half tombstone');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{1,amount_minor}','"50"')),'P0001','investment_cash_invalid_linked_move','money must remain a JSON integer rather than a numeric string');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',jsonb_set(pg_temp.rows(),'{0,accounting_amount_minor}','"-50"')),'P0001','investment_cash_invalid_linked_move','accounting delta must remain a JSON integer');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',(select jsonb_agg(value||jsonb_build_object('cash_origin_raw_value','derived')) from jsonb_array_elements(pg_temp.rows()))),'P0001','investment_cash_invalid_linked_move','changing both origins cannot launder a known manual move into derived cash');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',(select jsonb_agg(value||jsonb_build_object('role_raw_value','cashCorrection')) from jsonb_array_elements(pg_temp.rows()))),'P0001','investment_cash_invalid_linked_move','changing both roles cannot bypass canonical move validation');
-- The single-row upsert preserves the stored event_id; the compared API must
-- reject a spoofed incoming event before that immutable ancestry can be bypassed.
select throws_ok(format('select pg_temp.publish(%L::jsonb)',(select jsonb_agg(value||jsonb_build_object('event_id','61000000-0000-4000-8000-000000000503')) from jsonb_array_elements(pg_temp.rows()))),'P0001','Invalid investment cash posting','existing posting identities cannot disguise their immutable event ancestry');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',(select jsonb_agg(value||jsonb_build_object('ledger_transaction_id',public.investment_ledger_id('61000000-0000-4000-8000-000000000501','linked-wallet-move'))) from jsonb_array_elements(pg_temp.rows('61000000-0000-4000-8000-000000000503')))),'P0001','investment_cash_invalid_event_reference','new event identities cannot allocate another event real transfer again');
select is((select count(*) from public.investment_wallet_postings where event_id='61000000-0000-4000-8000-000000000503'),0::bigint,'spoofed event creates no extra investment cash postings');
select throws_ok(format('select pg_temp.publish(%L::jsonb)',pg_temp.rows('61000000-0000-4000-8000-000000000502','61000000-0000-4000-8000-000000000105','61000000-0000-4000-8000-000000000106','JPY')),'P0001','investment_cash_invalid_linked_move','matching JPY ledger and wallets cannot bypass the VND accounting root');
select is((select count(*) from public.investment_wallet_postings where event_id='61000000-0000-4000-8000-000000000502'),0::bigint,'wrong-root currency creates no postings');
select is((select min(sync_version) from public.investment_wallet_postings where event_id='61000000-0000-4000-8000-000000000501'),2::bigint,'rejected attempts keep the original compared versions');
select is((select count(*) from public.investment_wallet_postings where id='61000000-0000-4000-8000-000000000399'),0::bigint,'noncanonical row was never inserted');
select * from finish();
rollback;
