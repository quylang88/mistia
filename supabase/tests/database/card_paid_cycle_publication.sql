begin;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('71000000-0000-4000-8000-000000000001','authenticated','authenticated','card-rpc@mistia.test','',now(),'{"provider":"email"}','{}',now(),now()),
('71000000-0000-4000-8000-000000000002','authenticated','authenticated','card-rpc-other@mistia.test','',now(),'{"provider":"email"}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values('71000000-0000-4000-8000-000000000001','Local card RPC'),('71000000-0000-4000-8000-000000000002','Other local actor') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,created_at,updated_at,sync_version)
values('71000000-0000-4000-8000-000000000101','71000000-0000-4000-8000-000000000001','Cash','cash','banknote.fill','#111111','JPY',1000,'2026-08-01','2026-08-01',1),
('71000000-0000-4000-8000-000000000201','71000000-0000-4000-8000-000000000001','Card','creditCard','creditcard.fill','#111111','JPY',0,'2026-08-01','2026-08-01',1);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code)
values('71000000-0000-4000-8000-000000000102','71000000-0000-4000-8000-000000000002','Foreign cash','cash','banknote.fill','#111111','JPY');
insert into public.credit_card_profiles(id,user_id,network_raw_value,wallet_id,payment_source_wallet_id,credit_limit_minor,statement_closing_day,payment_due_day)
values('71000000-0000-4000-8000-000000000202','71000000-0000-4000-8000-000000000001','visa','71000000-0000-4000-8000-000000000201','71000000-0000-4000-8000-000000000101',1000,10,26);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,transfer_subtype_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,destination_wallet_id,source_currency_code,destination_currency_code,destination_amount_minor,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id,sync_version)
values('71000000-0000-4000-8000-000000000301','71000000-0000-4000-8000-000000000001','transfer','internalTransfer','posted','Card payment',70,'2026-10-28T00:01:00Z','71000000-0000-4000-8000-000000000101','71000000-0000-4000-8000-000000000201','JPY','JPY',70,'JPY',70,'71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001',1);
insert into public.ledger_transactions select (jsonb_populate_record(null::public.ledger_transactions,to_jsonb(t)||jsonb_build_object('id',v.id))).* from public.ledger_transactions t cross join (values('71000000-0000-4000-8000-000000000302'::uuid),('71000000-0000-4000-8000-000000000303'::uuid)) v(id) where t.id='71000000-0000-4000-8000-000000000301';
insert into public.ledger_transactions select (jsonb_populate_record(null::public.ledger_transactions,to_jsonb(t)||jsonb_build_object('id','71000000-0000-4000-8000-000000000399','user_id','71000000-0000-4000-8000-000000000002','source_wallet_id','71000000-0000-4000-8000-000000000102','created_by_user_id','71000000-0000-4000-8000-000000000002','last_modified_by_user_id','71000000-0000-4000-8000-000000000002','primary_kind_raw_value','expense','transfer_subtype_raw_value',null,'destination_wallet_id',null,'destination_amount_minor',null,'destination_currency_code',null))).* from public.ledger_transactions t where t.id='71000000-0000-4000-8000-000000000301';
insert into public.due_occurrence_records(id,user_id,source_kind_raw_value,source_id,selected_month_key,scheduled_date,amount_minor_snapshot,status_raw_value,paid_at,linked_transaction_id,created_at,updated_at,sync_version,last_modified_by_device_id)
values('71000000-0000-4000-8000-000000000499','71000000-0000-4000-8000-000000000002','creditCard','71000000-0000-4000-8000-000000000299','2026-09','2026-10-26',75,'paid','2026-10-28T00:01:00Z','71000000-0000-4000-8000-000000000399','2026-10-28T00:01:00Z','2026-10-28T00:01:00Z',1,'71000000-0000-4000-8000-000000000901');
create temporary table proof(name text primary key,l jsonb,w jsonb,s jsonb);
grant all on proof to authenticated;
create function pg_temp.cycle_payload(p_id uuid default '71000000-0000-4000-8000-000000000401',p_link uuid default '71000000-0000-4000-8000-000000000301',p_month text default '2026-09',p_target bigint default 1,p_deleted timestamptz default null,p_paid timestamptz default '2026-10-28T00:01:00Z') returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','71000000-0000-4000-8000-000000000001','source_kind_raw_value','creditCard','source_id','71000000-0000-4000-8000-000000000201','selected_month_key',p_month,'scheduled_date',((p_month||'-26')::date+interval '1 month')::timestamptz,'amount_minor_snapshot',70,'status_raw_value','paid','paid_at',p_paid,'linked_transaction_id',p_link,'created_at','2026-10-28T00:01:00Z','updated_at',coalesce(p_deleted,p_paid),'deleted_at',p_deleted,'sync_version',p_target,'last_modified_by_device_id','71000000-0000-4000-8000-000000000901')
$$;
create function pg_temp.capture(p_name text,p_links uuid[] default array['71000000-0000-4000-8000-000000000301'::uuid]) returns void language sql as $$
insert into proof select p_name,
(select jsonb_object_agg(x::text,(select to_jsonb(t) from public.ledger_transactions t where t.id=x)) from unnest(p_links) x),
(select jsonb_object_agg(w.id::text,to_jsonb(w)) from public.ledger_wallets w where w.user_id='71000000-0000-4000-8000-000000000001'),
coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from public.due_occurrence_records c where c.user_id='71000000-0000-4000-8000-000000000001' and c.source_kind_raw_value='creditCard' and c.source_id='71000000-0000-4000-8000-000000000201'),'[]'::jsonb)
$$;
create function pg_temp.publish(p_cycle jsonb default pg_temp.cycle_payload(),p_base bigint default 0,p_present boolean default false,p_proof text default 'initial') returns jsonb language sql as $$
select public.mutate_card_paid_cycle(p_cycle,p_base,p_present,l,w,s) from proof where name=p_proof
$$;
set local role authenticated;
select pg_temp.capture('initial');
select lives_ok($$select pg_temp.publish()$$,'new paid card marker publishes from actual owned transfer');
select is((select sync_version from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000401'),1::bigint,'new marker version1');
select throws_ok($$select pg_temp.publish()$$,'P0001','card_payment_version_conflict','stale absent0 cannot overwrite a committed marker');
select pg_temp.capture('created');
update public.ledger_transactions set deleted_at='2026-10-28T00:02:00Z',sync_version=2 where id='71000000-0000-4000-8000-000000000301';
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>2),1,true,'created')$$,'P0001','card_payment_ledger_changed','late active request fails after actual payment undo');
select pg_temp.capture('undo');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>2,p_deleted=>'2026-10-28T00:02:00Z'),1,true,'undo')$$,'actual deleted transfer permits only its marker tombstone');
select is((select deleted_at from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000401'),'2026-10-28T00:02:00Z'::timestamptz,'marker undo timestamp preserved');
update public.ledger_transactions set deleted_at=null,occurred_at='2026-10-28T00:04:00Z',sync_version=3 where id='71000000-0000-4000-8000-000000000301';
select pg_temp.capture('repay');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>3,p_paid=>'2026-10-28T00:04:00Z'),2,true,'repay')$$,'same ledger repay requires actual strictly later payment');
select pg_temp.capture('live');
update public.ledger_wallets set deleted_at='2026-10-28T00:05:00Z',sync_version=2 where id='71000000-0000-4000-8000-000000000201';
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'live')$$,'P0001','card_payment_wallet_changed','late request fails after card mutation');
select pg_temp.capture('deleted-card');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'deleted-card')$$,'P0001','card_payment_invalid_financial_footprint','observing a deleted card cannot authorize a new active marker');
update public.ledger_wallets set deleted_at=null,is_archived=true,sync_version=3 where id='71000000-0000-4000-8000-000000000201';
update public.ledger_wallets set is_archived=true,sync_version=2 where id='71000000-0000-4000-8000-000000000101';
update public.credit_card_profiles set payment_source_wallet_id=null,statement_closing_day=25,payment_due_day=30 where id='71000000-0000-4000-8000-000000000202';
select pg_temp.capture('history');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'history')$$,'archived wallets and current profile changes preserve posted history');
select is((select sync_version from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000401'),4::bigint,'history publication advances only marker');
select pg_temp.capture('guard');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')||'{"_mistia_android_spoof":true}',4,true,'guard')$$,'P0001','card_payment_invalid_group','closed marker rejects private fields');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')||'{"amount_minor_snapshot":"70"}',4,true,'guard')$$,'P0001','card_payment_invalid_group','minor values stay numeric');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')||'{"sync_version":"5"}',4,true,'guard')$$,'P0001','card_payment_invalid_group','versions stay numeric');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')-'deleted_at',4,true,'guard')$$,'P0001','card_payment_invalid_group','explicit nulls required');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')||'{"created_at":"2026-10-29T00:00:00Z"}',4,true,'guard')$$,'P0001','card_payment_invalid_identity','immutable marker birth protected');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')||'{"selected_month_key":"2026-06","scheduled_date":"2026-07-26T00:00:00Z"}',4,true,'guard')$$,'P0001','card_payment_invalid_identity','unrelated historical month cannot be relabelled');
select throws_ok($$select public.mutate_card_paid_cycle(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z'),4,true,l||'{"71000000-0000-4000-8000-000000000999":null}',w,s) from proof where name='guard'$$,'P0001','card_payment_invalid_group','unrequested compared ledger rejected');
select throws_ok($$select public.mutate_card_paid_cycle(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z'),4,true,jsonb_set(l,'{71000000-0000-4000-8000-000000000301,_mistia_android_spoof}','true'),w,s) from proof where name='guard'$$,'P0001','card_payment_invalid_group','private compared ledger rejected');
select throws_ok($$select public.mutate_card_paid_cycle(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z'),4,true,l,w,'[]') from proof where name='guard'$$,'P0001','card_payment_membership_changed','full all-month card membership required');
-- An existing0 identity is distinct from an absent0 birth; legacy overpayment remains valid.
insert into public.due_occurrence_records select (jsonb_populate_record(null::public.due_occurrence_records,pg_temp.cycle_payload('71000000-0000-4000-8000-000000000402','71000000-0000-4000-8000-000000000302','2026-10',0)||'{"status_raw_value":"pending","paid_at":null,"linked_transaction_id":null}')).*;
select pg_temp.capture('zero',array['71000000-0000-4000-8000-000000000302'::uuid]);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload('71000000-0000-4000-8000-000000000402','71000000-0000-4000-8000-000000000302','2026-10'),0,false,'zero')$$,'P0001','card_payment_version_conflict','absent0 cannot replace observed0');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload('71000000-0000-4000-8000-000000000402','71000000-0000-4000-8000-000000000302','2026-10')||'{"amount_minor_snapshot":69}',0,true,'zero')$$,'observed0 pending marker accepts existing transfer covering a smaller statement');
select is((select amount_minor_snapshot from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000402'),69::bigint,'legacy overpayment marker does not rewrite actual70');
select pg_temp.capture('foreign',array['71000000-0000-4000-8000-000000000303'::uuid]);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload('71000000-0000-4000-8000-000000000499','71000000-0000-4000-8000-000000000303','2026-12'),0,false,'foreign')$$,'P0001','card_payment_version_conflict','RLS-hidden foreign globalID is preserved at the actual write boundary');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z')||'{"user_id":"71000000-0000-4000-8000-000000000002"}',4,true,'foreign')$$,'P0001','card_payment_owner_required','authenticated actor cannot assert another owner');
select is((select count(*) from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000499'),0::bigint,'unrelated foreign marker stays invisible through RLS');
select is((select count(*) from public.ledger_transactions where id='71000000-0000-4000-8000-000000000399'),0::bigint,'foreign ledger fixture is actually RLS-hidden');
select is((select count(*) from public.ledger_wallets where id='71000000-0000-4000-8000-000000000102'),0::bigint,'foreign source fixture is actually RLS-hidden');
select pg_temp.capture('foreign-ledger',array['71000000-0000-4000-8000-000000000399'::uuid]);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload('71000000-0000-4000-8000-000000000498','71000000-0000-4000-8000-000000000399','2026-12',1,'2026-10-28T00:09:00Z'),0,false,'foreign-ledger')$$,'P0001','card_payment_ledger_changed','a hidden live foreign ledger cannot be treated as absent for a tombstone birth');
select throws_ok($$select public.mutate_card_paid_cycle(pg_temp.cycle_payload('71000000-0000-4000-8000-000000000497','71000000-0000-4000-8000-000000000999','2026-12',1,'2026-10-28T00:09:00Z')||'{"source_id":"71000000-0000-4000-8000-000000000102"}',0,false,'{"71000000-0000-4000-8000-000000000999":null}','{"71000000-0000-4000-8000-000000000102":null}','[]')$$,'P0001','card_payment_wallet_changed','a hidden foreign source cannot authorize even an owned tombstone marker');
-- A legacy due-month sibling with the same frozen schedule must be reconciled.
insert into public.due_occurrence_records select (jsonb_populate_record(null::public.due_occurrence_records,pg_temp.cycle_payload('71000000-0000-4000-8000-000000000404','71000000-0000-4000-8000-000000000303','2026-10')||'{"scheduled_date":"2026-10-26T00:00:00Z"}')).*;
select pg_temp.capture('sibling');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z'),4,true,'sibling')$$,'P0001','card_payment_financial_sibling_conflict','legacy due-month sibling prevents duplicate paid attribution');
delete from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000404';
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>5,p_paid=>'2026-10-28T00:04:00Z'),4,true,'sibling')$$,'P0001','card_payment_membership_changed','late membership removal invalidates the captured write');
-- Lost old replies plus a different new payment require the old money to be dead.
update public.due_occurrence_records set deleted_at='2026-10-28T00:06:00Z' where id='71000000-0000-4000-8000-000000000401';
update public.ledger_transactions set occurred_at='2026-10-28T00:08:00Z',amount_minor=9007199254740993,destination_amount_minor=9007199254740993 where id='71000000-0000-4000-8000-000000000303';
select pg_temp.capture('old-live',array['71000000-0000-4000-8000-000000000301'::uuid,'71000000-0000-4000-8000-000000000303'::uuid]);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_link=>'71000000-0000-4000-8000-000000000303',p_target=>5,p_paid=>'2026-10-28T00:08:00Z')||'{"amount_minor_snapshot":9007199254740993}',4,true,'old-live')$$,'P0001','card_payment_invalid_transition','different payment cannot steal a marker from still-live money');
update public.ledger_transactions set deleted_at='2026-10-28T00:06:00Z',is_archived=true,archived_at='2026-10-28T00:06:00Z',sync_version=4 where id='71000000-0000-4000-8000-000000000301';
select pg_temp.capture('new-payment',array['71000000-0000-4000-8000-000000000301'::uuid,'71000000-0000-4000-8000-000000000303'::uuid]);
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_link=>'71000000-0000-4000-8000-000000000303',p_target=>5,p_paid=>'2026-10-28T00:08:00Z')||'{"amount_minor_snapshot":9007199254740993}',4,true,'new-payment')$$,'strict later payment can follow archived and deleted financial history');
select is((select amount_minor_snapshot from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000401'),9007199254740993::bigint,'minor amount above Double range stays exact');
select pg_temp.capture('exact-long',array['71000000-0000-4000-8000-000000000303'::uuid]);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_link=>'71000000-0000-4000-8000-000000000303',p_target=>6,p_paid=>'2026-10-28T00:08:00Z')||'{"amount_minor_snapshot":9007199254740992}',5,true,'exact-long')$$,'P0001','card_payment_invalid_transition','already-paid historical amount cannot be silently relabelled');
-- Marker mutations never touch ledger/wallet/posting state.
create temporary table financial_before as select jsonb_build_object('ledger',(select jsonb_agg(to_jsonb(t) order by id) from public.ledger_transactions t),'wallet',(select jsonb_agg(to_jsonb(w) order by id) from public.ledger_wallets w),'posting',(select jsonb_agg(to_jsonb(p) order by id) from public.investment_wallet_postings p)) as body;
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_link=>'71000000-0000-4000-8000-000000000303',p_target=>6,p_paid=>'2026-10-28T00:08:00Z')||'{"amount_minor_snapshot":9007199254740993}',5,true,'exact-long')$$,'same historical facts may retry through compared marker update');
select is(jsonb_build_object('ledger',(select jsonb_agg(to_jsonb(t) order by id) from public.ledger_transactions t),'wallet',(select jsonb_agg(to_jsonb(w) order by id) from public.ledger_wallets w),'posting',(select jsonb_agg(to_jsonb(p) order by id) from public.investment_wallet_postings p)),(select body from financial_before),'no ledger wallet or allocation side effects');
select is((select prosecdef from pg_proc where oid='public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb)'::regprocedure),true,'closed definer distinguishes actual foreign identities from absence');
select is((select proconfig from pg_proc where oid='public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb)'::regprocedure),array['search_path=pg_catalog, public'],'definer search path is pinned');
select ok(not has_function_privilege('anon','public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb)','EXECUTE'),'anon has no writer capability');
select ok(not has_function_privilege('service_role','public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb)','EXECUTE'),'service role has no direct writer grant');
select ok(has_function_privilege('authenticated','public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb)','EXECUTE'),'authenticated closed writer capability');
reset role;
select is((select amount_minor_snapshot from public.due_occurrence_records where id='71000000-0000-4000-8000-000000000499'),75::bigint,'foreign global identity value unchanged');
select * from finish();
rollback;
