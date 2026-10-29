begin;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('67000000-0000-4000-8000-000000000001','authenticated','authenticated','installment-characterization@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values('67000000-0000-4000-8000-000000000001','Local installment characterization') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','67000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values('67000000-0000-4000-8000-000000000101','67000000-0000-4000-8000-000000000001','Cash','cash','banknote.fill','#111111','JPY',1000);
insert into public.installment_plans(id,user_id,name,icon_symbol_name,amount_per_cycle_minor,due_day,total_cycles,frequency_months,payment_wallet_id,currency_code,created_at,updated_at,sync_version)
values('67000000-0000-4000-8000-000000000201','67000000-0000-4000-8000-000000000001','Installment','mistia.plan.installment',70,28,12,1,'67000000-0000-4000-8000-000000000101','JPY','2026-10-28T00:00:00Z','2026-10-28T00:00:00Z',1);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id,sync_version)
values('67000000-0000-4000-8000-000000000301','67000000-0000-4000-8000-000000000001','expense','posted','Payment',70,'2026-10-28T00:01:00Z','67000000-0000-4000-8000-000000000101','JPY','JPY',70,'67000000-0000-4000-8000-000000000001','67000000-0000-4000-8000-000000000001',1);

insert into public.ledger_transactions select (jsonb_populate_record(null::public.ledger_transactions,to_jsonb(t)||jsonb_build_object('id',v.id))).* from public.ledger_transactions t cross join (values('67000000-0000-4000-8000-000000000302'::uuid),('67000000-0000-4000-8000-000000000303'::uuid)) v(id) where t.id='67000000-0000-4000-8000-000000000301';
create temporary table proof(name text primary key,p jsonb,l jsonb,w jsonb,s jsonb);
grant all on proof to authenticated;
create function pg_temp.cycle_payload(p_id uuid default '67000000-0000-4000-8000-000000000401',p_link uuid default '67000000-0000-4000-8000-000000000301',p_month text default '2026-10',p_target bigint default 1,p_deleted timestamptz default null,p_paid timestamptz default '2026-10-28T00:01:00Z') returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','67000000-0000-4000-8000-000000000001','source_kind_raw_value','installment','source_id','67000000-0000-4000-8000-000000000201','selected_month_key',p_month,'scheduled_date',(p_month||'-28T00:00:00Z')::timestamptz,'amount_minor_snapshot',70,'status_raw_value','paid','paid_at',p_paid,'linked_transaction_id',p_link,'created_at','2026-10-28T00:01:00Z','updated_at',coalesce(p_deleted,p_paid),'deleted_at',p_deleted,'sync_version',p_target,'last_modified_by_device_id','67000000-0000-4000-8000-000000000901')
$$;
create function pg_temp.capture(p_name text,p_cycle jsonb default pg_temp.cycle_payload()) returns void language sql as $$
insert into proof select p_name,to_jsonb(p),to_jsonb(l),to_jsonb(w),coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from public.due_occurrence_records c where c.user_id=p.user_id and c.source_kind_raw_value='installment' and c.source_id=p.id and c.selected_month_key=p_cycle->>'selected_month_key'),'[]'::jsonb)
from public.installment_plans p left join public.ledger_transactions l on l.id=(p_cycle->>'linked_transaction_id')::uuid left join public.ledger_wallets w on w.id=l.source_wallet_id where p.id=(p_cycle->>'source_id')::uuid;
$$;
create function pg_temp.publish(p_cycle jsonb default pg_temp.cycle_payload(),p_base bigint default 0,p_present boolean default false,p_proof text default 'initial') returns jsonb language sql as $$
select public.mutate_installment_paid_cycle(p_cycle,p_base,p_present,p,l,w,s) from proof where name=p_proof
$$;
set local role authenticated;
select pg_temp.capture('initial');
select lives_ok($$select pg_temp.publish()$$,'new paid cycle publishes with exact source ledger wallet and absence comparisons');
select is((select sync_version from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000401'),1::bigint,'new marker version1');
select is((select amount_minor_snapshot from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000401'),70::bigint,'frozen amount exact');
select throws_ok($$select pg_temp.publish()$$,'P0001','installment_payment_version_conflict','stale absence cannot overwrite a committed identity');
select pg_temp.capture('created');
update public.ledger_transactions set deleted_at='2026-10-28T00:02:00Z',sync_version=2 where id='67000000-0000-4000-8000-000000000301';
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>2),1,true,'created')$$,'P0001','installment_payment_ledger_changed','late active request rejected after real ledger undo');
select pg_temp.capture('undo');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>2,p_deleted=>'2026-10-28T00:02:00Z'),1,true,'undo')$$,'exact deleted financial proof permits marker tombstone');
select is((select sync_version from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000401'),2::bigint,'undo marker version2');
update public.ledger_transactions set deleted_at=null,occurred_at='2026-10-28T00:04:00Z',sync_version=3 where id='67000000-0000-4000-8000-000000000301';
select pg_temp.capture('repay');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>3,p_paid=>'2026-10-28T00:04:00Z'),2,true,'repay')$$,'re-pay preserves cycle birth and compares tombstoned history');
select pg_temp.capture('repay-live');
update public.installment_plans set deleted_at='2026-10-28T00:05:00Z',sync_version=2 where id='67000000-0000-4000-8000-000000000201';
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'repay-live')$$,'P0001','installment_payment_source_changed','late request rejected after source deletion');
update public.installment_plans set deleted_at=null,sync_version=3 where id='67000000-0000-4000-8000-000000000201';
select pg_temp.capture('current');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z')||'{"amount_minor_snapshot":69}',3,true,'current')$$,'P0001','installment_payment_invalid_financial_footprint','cycle amount must match actual compared ledger');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z')||'{"_mistia_android_spoof":true}',3,true,'current')$$,'P0001','installment_payment_invalid_group','unknown local-only fields rejected');
select throws_ok($$select public.mutate_installment_paid_cycle(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,p,l,w,'[]') from proof where name='current'$$,'P0001','installment_payment_membership_changed','complete current month membership required');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z')||'{"created_at":"2026-10-29T00:01:00Z"}',3,true,'current')$$,'P0001','installment_payment_invalid_identity','immutable cycle birth protected');
-- A real existing0 is distinct from an absent0.
insert into public.due_occurrence_records select (jsonb_populate_record(null::public.due_occurrence_records,pg_temp.cycle_payload('67000000-0000-4000-8000-000000000402','67000000-0000-4000-8000-000000000302','2026-11',0))).*;
update public.ledger_transactions set deleted_at='2026-10-28T00:02:00Z',sync_version=2 where id='67000000-0000-4000-8000-000000000302';
select pg_temp.capture('zero',pg_temp.cycle_payload('67000000-0000-4000-8000-000000000402','67000000-0000-4000-8000-000000000302','2026-11'));
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000402','67000000-0000-4000-8000-000000000302','2026-11',1,'2026-10-28T00:02:00Z'),0,false,'zero')$$,'P0001','installment_payment_version_conflict','absence0 cannot replace observed0');
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000402','67000000-0000-4000-8000-000000000302','2026-11',1,'2026-10-28T00:02:00Z'),0,true,'zero')$$,'observed0 advances to1 under explicit presence');
select is((select sync_version from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000402'),1::bigint,'existing0 exact version1');
select pg_temp.capture('missing',pg_temp.cycle_payload('67000000-0000-4000-8000-000000000403','67000000-0000-4000-8000-000000000303','2026-12'));
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000403','67000000-0000-4000-8000-000000000303','2026-12'),0,true,'missing')$$,'P0001','installment_payment_version_conflict','expected-existing absent0 is not recreated');
select is((select count(*) from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000403'),0::bigint,'failed comparison leaves no partial cycle');
select is((select amount_minor from public.ledger_transactions where id='67000000-0000-4000-8000-000000000301'),70::bigint,'marker workflow never rewrites money');

-- All compared objects are closed typed observations, never local-private state.
select throws_ok($$select public.mutate_installment_paid_cycle(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,p||'{"_mistia_android_spoof":true}',l,w,s) from proof where name='current'$$,'P0001','installment_payment_invalid_group','private compared plan evidence rejected');
select throws_ok($$select public.mutate_installment_paid_cycle(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,p,l||'{"_mistia_android_spoof":true}',w,s) from proof where name='current'$$,'P0001','installment_payment_invalid_group','private compared ledger evidence rejected');
select throws_ok($$select public.mutate_installment_paid_cycle(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,p,l,w||'{"_mistia_android_spoof":true}',s) from proof where name='current'$$,'P0001','installment_payment_invalid_group','private compared wallet evidence rejected');
select throws_ok($$select public.mutate_installment_paid_cycle(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,jsonb_set(p,'{sync_version}','"3"'),l,w,s) from proof where name='current'$$,'P0001','installment_payment_invalid_group','comparison versions remain numeric Long');
update public.ledger_wallets set name='Renamed',sync_version=2 where id='67000000-0000-4000-8000-000000000101';
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'current')$$,'P0001','installment_payment_wallet_changed','wallet drift rejected before marker write');
update public.ledger_wallets set kind_raw_value='futureUnknownKind',sync_version=3 where id='67000000-0000-4000-8000-000000000101';
select pg_temp.capture('unknown-wallet');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'unknown-wallet')$$,'P0001','installment_payment_invalid_financial_footprint','unknown wallet kind cannot authorize financial marker');
update public.ledger_wallets set kind_raw_value='cash',sync_version=4 where id='67000000-0000-4000-8000-000000000101';
select pg_temp.capture('guard');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z')||'{"amount_minor_snapshot":"70"}',3,true,'guard')$$,'P0001','installment_payment_invalid_group','string minor amount rejected');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z')||'{"selected_month_key":null}',3,true,'guard')$$,'P0001','installment_payment_invalid_group','null cycle month rejected');
select set_config('request.jwt.claim.sub','67000000-0000-4000-8000-000000000002',true);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'guard')$$,'P0001','installment_payment_owner_required','another authenticated caller cannot publish owner cycle');
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,'guard')$$,'P0001','installment_payment_authentication_required','authenticated role without subject is insufficient');
select set_config('request.jwt.claim.sub','67000000-0000-4000-8000-000000000001',true);
-- Non-UTC local midnight must retain its instant, not become UTC due-day28.
select pg_temp.capture('jst',pg_temp.cycle_payload('67000000-0000-4000-8000-000000000403','67000000-0000-4000-8000-000000000303','2026-12'));
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000403','67000000-0000-4000-8000-000000000303','2026-12')||'{"scheduled_date":"2026-12-27T15:00:00Z"}',0,false,'jst')$$,'Tokyo local December28 midnight is preserved as December27UTC');
select is((select scheduled_date from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000403'),'2026-12-27T15:00:00Z'::timestamptz,'stored scheduling instant exact');
-- Full delete birth is a real identity fence even when its expense never reached cloud.
select pg_temp.capture('fence',pg_temp.cycle_payload('67000000-0000-4000-8000-000000000404','67000000-0000-4000-8000-000000000304','2027-01'));
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000404','67000000-0000-4000-8000-000000000304','2027-01',1,'2026-10-28T00:02:00Z'),0,false,'fence')$$,'unobserved0 undo creates complete compared tombstone fence');
select is((select sync_version from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000404'),1::bigint,'fence establishes observed version1');
-- Derived wallet cache is intentionally outside wallet metadata comparisons.
select is((select current_balance_minor from public.ledger_wallets where id='67000000-0000-4000-8000-000000000101'),860::bigint,'marker operations never modify wallet balance');
select ok(has_function_privilege('authenticated','public.mutate_installment_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb,jsonb)','execute'),'authenticated role explicitly granted closed RPC');
select ok(not has_function_privilege('anon','public.mutate_installment_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb,jsonb)','execute'),'anonymous role cannot call closed RPC');
update public.due_occurrence_records set sync_version=9007199254740993 where id='67000000-0000-4000-8000-000000000404';
select pg_temp.capture('long',pg_temp.cycle_payload('67000000-0000-4000-8000-000000000404','67000000-0000-4000-8000-000000000304','2027-01'));
select lives_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000404','67000000-0000-4000-8000-000000000304','2027-01',9007199254740994,'2026-10-28T00:02:00Z'),9007199254740993,true,'long')$$,'compared version above2pow53 advances exactly');
select is((select sync_version from public.due_occurrence_records where id='67000000-0000-4000-8000-000000000404'),9007199254740994::bigint,'database Long version is exact');
select throws_ok($$select pg_temp.publish(pg_temp.cycle_payload('67000000-0000-4000-8000-000000000404','67000000-0000-4000-8000-000000000304','2027-01',9223372036854775807,'2026-10-28T00:02:00Z'),9223372036854775807,true,'long')$$,'P0001','installment_payment_invalid_group','version increment cannot overflow');
-- A forced exception rolls back an unexpectedly accepted negative probe too.
select throws_ok($$do $probe$ begin
perform public.mutate_installment_paid_cycle(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z'),3,true,p,l,w,jsonb_set(s,'{0,sync_version}','"3"')) from proof where name='guard';
raise exception 'invalid_probe_was_accepted' using errcode='P0002';
end $probe$;$$,'P0001','installment_payment_invalid_group','sibling comparison versions are numeric without coercion');
select throws_ok($$do $probe$ begin
perform pg_temp.publish(pg_temp.cycle_payload(p_target=>4,p_paid=>'2026-10-28T00:04:00Z')||'{"last_modified_by_device_id":"ABCD0000-0000-4000-8000-000000000901"}',3,true,'guard');
raise exception 'invalid_probe_was_accepted' using errcode='P0002';
end $probe$;$$,'P0001','installment_payment_invalid_group','write audit UUIDs remain canonical in exact receipts');
select * from finish();
rollback;
