begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();
-- Synthetic legacy booked income supplies the exact ordinary example: actual100, booked60, normal40.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('65000000-0000-4000-8000-000000000001','authenticated','authenticated','ordinary-allocation@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('65000000-0000-4000-8000-000000000001','Ordinary allocation fixture') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('65000000-0000-4000-8000-000000000101','65000000-0000-4000-8000-000000000001','Cash','cash','banknote.fill','#111111','JPY',40),
('65000000-0000-4000-8000-000000000102','65000000-0000-4000-8000-000000000001','Destination','cash','banknote.fill','#111111','JPY',0);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,system_purpose_raw_value,investment_linked_wallet_id)
values (public.investment_system_wallet_id('65000000-0000-4000-8000-000000000001'),'65000000-0000-4000-8000-000000000001','Investment','investment','chart.line.uptrend.xyaxis','#9A67FF','JPY',0,'investmentProfit','65000000-0000-4000-8000-000000000101');
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values ('65000000-0000-4000-8000-000000000201','65000000-0000-4000-8000-000000000001','income','posted','Imported booked income',60,'2026-10-28T00:00:00Z','65000000-0000-4000-8000-000000000101','JPY','JPY',60,'65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000001'),
('65000000-0000-4000-8000-000000000301','65000000-0000-4000-8000-000000000001','expense','posted','Expense',70,'2026-10-28T00:02:00Z','65000000-0000-4000-8000-000000000101','JPY','JPY',70,'65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000001');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at,sync_version)
values ('65000000-0000-4000-8000-000000000202','65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000201','65000000-0000-4000-8000-000000000101','65000000-0000-4000-8000-000000000201','cashAccrual','booked','derived',60,'JPY',60,'JPY','2026-10-28T00:00:00Z',1);
create function pg_temp.consumption(p_event uuid,p_amount bigint default -30,p_component text default 'cash-consumption-booked',p_wallet uuid default '65000000-0000-4000-8000-000000000101',p_deleted timestamptz default null) returns jsonb language sql as $$
select jsonb_build_object('id',public.investment_ledger_id(p_event,p_component),'user_id','65000000-0000-4000-8000-000000000001','event_id',p_event,'ledger_transaction_id',p_event,
'wallet_id',p_wallet,'trade_id',null,'asset_id',null,'role_raw_value',case when p_event='65000000-0000-4000-8000-000000000302'::uuid then 'cashTransfer' else 'cashConsumption' end,
'cash_bucket_raw_value','booked','cash_origin_raw_value','derived','amount_minor',p_amount,'accounting_amount_minor',p_amount,'currency_code','JPY','accounting_currency_code','JPY',
'occurred_at','2026-10-28T00:02:00Z','created_at','2026-10-28T00:02:00Z','updated_at','2026-10-28T00:03:00Z','deleted_at',p_deleted,'last_modified_by_device_id','65000000-0000-4000-8000-000000000901')
$$;
create function pg_temp.publish_expense(p_amount bigint,p_base bigint,p_deleted timestamptz default null) returns setof public.investment_wallet_postings language sql as $$
select * from public.mutate_investment_cash_postings(jsonb_build_array(pg_temp.consumption('65000000-0000-4000-8000-000000000301',p_amount,'cash-consumption-booked','65000000-0000-4000-8000-000000000101',p_deleted)),jsonb_build_object(public.investment_ledger_id('65000000-0000-4000-8000-000000000301','cash-consumption-booked'),p_base),false)
$$;
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000101'),30::bigint,'real expense already consumes70 of actual100');
select lives_ok($$select * from pg_temp.publish_expense(-30,0)$$,'compared RPC accepts exact derived ordinary consumption');
select is((select accounting_amount_minor from public.investment_wallet_postings where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000301','cash-consumption-booked')),-30::bigint,'canonical ordinary consumption is exact');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where user_id='65000000-0000-4000-8000-000000000001' and deleted_at is null),30::bigint,'booked30 agrees with actual30 after publication');
update public.ledger_transactions set amount_minor=80,reporting_amount_minor=80,sync_version=2 where id='65000000-0000-4000-8000-000000000301';
select lives_ok($$select * from pg_temp.publish_expense(-40,1)$$,'compared RPC accepts derived ordinary edit while parent lives');
select is((select sync_version from public.investment_wallet_postings where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000301','cash-consumption-booked')),2::bigint,'edit advances canonical version exactly once');
select throws_ok($$select * from pg_temp.publish_expense(-35,1)$$,'P0001','version_conflict','ordinary allocation preserves strict comparison');
update public.ledger_transactions set is_archived=true,archived_at='2026-10-28T00:04:00Z',sync_version=3 where id='65000000-0000-4000-8000-000000000301';
select lives_ok($$select * from pg_temp.publish_expense(-40,2,'2026-10-28T00:04:00Z')$$,'archived but alive parent still permits allocation retirement');
update public.ledger_transactions set is_archived=false,archived_at=null,sync_version=4 where id='65000000-0000-4000-8000-000000000301';
select lives_ok($$select * from pg_temp.publish_expense(-40,3)$$,'restored live parent permits allocation restoration');
-- Existing generic parent publication happens first. Its deletion makes the cash RPC refuse the remaining tombstone.
update public.ledger_transactions set deleted_at='2026-10-28T00:05:00Z',sync_version=5 where id='65000000-0000-4000-8000-000000000301';
select throws_ok($$select * from pg_temp.publish_expense(-40,4,'2026-10-28T00:05:00Z')$$,'P0001','Investment cash ledger transaction is missing','legacy posting API retains its live-parent prerequisite');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where user_id='65000000-0000-4000-8000-000000000001' and deleted_at is null),20::bigint,'legacy partial deletion demonstrably leaves booked20');

create function pg_temp.expected_presence(t jsonb,posts jsonb,adjustment jsonb default null) returns jsonb language sql as $$
 select jsonb_object_agg(id,present) from (
  select t->>'id' id,exists(select 1 from public.ledger_transactions r where r.id=(t->>'id')::uuid) present
  union all select adjustment->>'id',exists(select 1 from public.ledger_transactions r where r.id=(adjustment->>'id')::uuid) where adjustment is not null
  union all select x->>'id',exists(select 1 from public.investment_wallet_postings r where r.id=(x->>'id')::uuid) from jsonb_array_elements(posts) x
 ) flags
$$;
create function pg_temp.atomic_expense(p_base bigint,p_post_base bigint,p_amount bigint default 80,p_used bigint default -40,p_deleted timestamptz default null,p_archive boolean default false) returns jsonb language plpgsql as $$
declare t jsonb; p jsonb;
begin
 select to_jsonb(r) into t from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000301';
 t:=t || jsonb_build_object('amount_minor',p_amount,'reporting_amount_minor',p_amount,'sync_version',p_base,'deleted_at',p_deleted,'is_archived',p_archive,'archived_at',case when p_archive then '2026-10-28T00:06:00Z' end,'last_modified_by_device_id','65000000-0000-4000-8000-000000000901');
 p:=pg_temp.consumption('65000000-0000-4000-8000-000000000301',p_used,'cash-consumption-booked','65000000-0000-4000-8000-000000000101',case when p_archive then '2026-10-28T00:06:00Z'::timestamptz else p_deleted end) || jsonb_build_object('sync_version',p_post_base);
 return public.mutate_ordinary_investment_event(t,null,jsonb_build_array(p),p_base,0,jsonb_build_object(p->>'id',p_post_base),pg_temp.expected_presence(t,jsonb_build_array(p)));
end $$;
select lives_ok($$select pg_temp.atomic_expense(5,4,80,-40,'2026-10-28T00:05:00Z')$$,'atomic API recovers parent-deleted legacy partial allocation');
select ok((select deleted_at is not null from public.investment_wallet_postings where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000301','cash-consumption-booked')),'deleted ordinary event leaves no active consumed investment money');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where user_id='65000000-0000-4000-8000-000000000001' and deleted_at is null),60::bigint,'atomic deletion restores exact original booked60');
select lives_ok($$select pg_temp.atomic_expense(6,5)$$,'atomic restore revives parent and allocation together');
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000101'),20::bigint,'actual balance restored exactly');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where user_id='65000000-0000-4000-8000-000000000001' and deleted_at is null),20::bigint,'booked balance restored exactly');
select throws_ok($$select pg_temp.atomic_expense(6,6,75,-35)$$,'P0001','ordinary_investment_version_conflict','stale parent comparison rejects whole group');
select throws_ok($$select pg_temp.atomic_expense(7,5,75,-35)$$,'P0001','ordinary_investment_version_conflict','stale allocation comparison rejects whole group');
select is((select amount_minor from public.ledger_transactions where id='65000000-0000-4000-8000-000000000301'),80::bigint,'failed comparisons preserve parent');
select lives_ok($$select pg_temp.atomic_expense(7,6,75,-35)$$,'atomic ordinary edit changes both amounts');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where user_id='65000000-0000-4000-8000-000000000001' and deleted_at is null),25::bigint,'edited allocation retains booked25');
select lives_ok($$select pg_temp.atomic_expense(8,7,75,-35,null,true)$$,'archive retires allocation atomically');
select lives_ok($$select pg_temp.atomic_expense(9,8,75,-35)$$,'archive restoration republishes full group');
select throws_ok($$select pg_temp.atomic_expense(10,9,75,-61)$$,'P0001','ordinary_investment_capacity_conflict','overdraw rejects entire parent and posting update');
select is((select sync_version from public.ledger_transactions where id='65000000-0000-4000-8000-000000000301'),10::bigint,'failed capacity leaves parent version unchanged');

-- Closed authority: use the actual authenticated role, not the DB owner's RLS bypass.
set local role authenticated;
create function pg_temp.atomic_current(t_patch jsonb default '{}',p_patch jsonb default '{}') returns jsonb language plpgsql as $$
declare t jsonb;p jsonb;b bigint;pb bigint;
begin
 select to_jsonb(r),r.sync_version into t,b from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000301';
 select to_jsonb(r),r.sync_version into p,pb from public.investment_wallet_postings r where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000301','cash-consumption-booked');
 return public.mutate_ordinary_investment_event(t||t_patch,null,jsonb_build_array(p||p_patch),b,0,jsonb_build_object(p->>'id',pb),pg_temp.expected_presence(t||t_patch,jsonb_build_array(p||p_patch)));
end $$;
select throws_ok($$select pg_temp.atomic_current('{"settlement_role_raw_value":"billPayment"}')$$,'P0001','ordinary_investment_invalid_parent','ordinary API cannot rewrite a paid bill');
select throws_ok($$select pg_temp.atomic_current('{"primary_kind_raw_value":null}')$$,'P0001','ordinary_investment_invalid_parent','null parent kind is rejected before any write');
select throws_ok($$select pg_temp.atomic_current('{"_mistia_android_fake_proof":true}')$$,'P0001','ordinary_investment_invalid_group','local publication journals never reach wire');
select throws_ok($$select pg_temp.atomic_current('{"amount_minor":"75"}')$$,'P0001','ordinary_investment_invalid_group','numeric strings are not exact JSON minor amounts');
select throws_ok($$select pg_temp.atomic_current('{}','{"cash_origin_raw_value":"manual"}')$$,'P0001','ordinary_investment_invalid_posting','manual posting cannot launder ordinary allocation');
select throws_ok($$select pg_temp.atomic_current('{}','{"event_id":"65000000-0000-4000-8000-000000000999"}')$$,'P0001','ordinary_investment_invalid_posting','derived identity cannot be rebound');
select throws_ok($$select pg_temp.atomic_current('{}','{"wallet_id":null}')$$,'P0001','ordinary_investment_invalid_posting','null wallet is never treated as a valid owned wallet');
select throws_ok($$select pg_temp.atomic_current(jsonb_build_object('source_wallet_id',public.investment_system_wallet_id('65000000-0000-4000-8000-000000000001'),'deleted_at','2026-10-28T01:00:00Z'),'{"deleted_at":"2026-10-28T01:00:00Z"}')$$,'P0001','ordinary_investment_invalid_wallet','tombstone cannot turn ordinary event into an unguarded system-wallet transfer');
select ok(not has_function_privilege('anon','public.mutate_ordinary_investment_event(jsonb,jsonb,jsonb,bigint,bigint,jsonb,jsonb)','execute'),'anonymous role cannot invoke atomic writer');
select ok(has_function_privilege('authenticated','public.mutate_ordinary_investment_event(jsonb,jsonb,jsonb,bigint,bigint,jsonb,jsonb)','execute'),'authenticated role has explicit entry point');
reset role;
-- A negative unrelated root reserve is allowed existing financial history. It
-- cannot block an ordinary event affecting only the source's booked bucket.
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at)
values('65000000-0000-4000-8000-000000000209','65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000201',public.investment_system_wallet_id('65000000-0000-4000-8000-000000000001'),'65000000-0000-4000-8000-000000000201','cashAccrual','unreconciled','derived',-10,'JPY',-10,'JPY','2026-10-28T00:01:00Z');
set local role authenticated;
select lives_ok($$select pg_temp.atomic_current()$$,'unrelated negative reserve does not block booked-only publication');
reset role;
delete from public.investment_wallet_postings where id='65000000-0000-4000-8000-000000000209';

create function pg_temp.new_parent(n integer,source uuid default '65000000-0000-4000-8000-000000000101',amount bigint default 10,destination uuid default null) returns jsonb language sql as $$
 select to_jsonb(r)||jsonb_build_object('id',('65000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'sync_version',0,'deleted_at',null,'is_archived',false,'archived_at',null,'created_at','2026-10-28T01:00:00Z','updated_at','2026-10-28T01:00:00Z','occurred_at','2026-10-28T01:00:00Z','source_wallet_id',source,'destination_wallet_id',destination,'destination_currency_code',case when destination is not null then 'JPY' end,'destination_amount_minor',case when destination is not null then amount end,'primary_kind_raw_value',case when destination is null then 'expense' else 'transfer' end,'transfer_subtype_raw_value',case when destination is not null then 'internalTransfer' end,'amount_minor',amount,'reporting_amount_minor',amount)
 from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000301'
$$;
create function pg_temp.new_post(n integer,amount bigint default -10,component text default 'cash-consumption-booked',wallet uuid default '65000000-0000-4000-8000-000000000101',role text default 'cashConsumption',bucket text default 'booked') returns jsonb language sql as $$
 select pg_temp.consumption(('65000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,amount,component,wallet)||jsonb_build_object('sync_version',0,'role_raw_value',role,'cash_bucket_raw_value',bucket,'created_at','2026-10-28T01:00:00Z','updated_at','2026-10-28T01:00:00Z','occurred_at','2026-10-28T01:00:00Z')
$$;
create function pg_temp.atomic_group(t jsonb,posts jsonb,adjustment jsonb default null) returns jsonb language sql as $$
 select public.mutate_ordinary_investment_event(t,adjustment,posts,(t->>'sync_version')::bigint,coalesce((adjustment->>'sync_version')::bigint,0),(select jsonb_object_agg(value->>'id',value->'sync_version') from jsonb_array_elements(posts)),pg_temp.expected_presence(t,posts,adjustment))
$$;
set local role authenticated;
select lives_ok($$select pg_temp.atomic_group(pg_temp.new_parent(303),jsonb_build_array(pg_temp.new_post(303)))$$,'authenticated ordinary create publishes parent and booked allocation');
select is((select sync_version from public.ledger_transactions where id='65000000-0000-4000-8000-000000000303'),1::bigint,'atomic create has compared initial version1');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000101' and deleted_at is null),15::bigint,'new expense leaves booked15');
select throws_ok($$select pg_temp.atomic_group(pg_temp.new_parent(304,'65000000-0000-4000-8000-000000000101',10,'65000000-0000-4000-8000-000000000102'),jsonb_build_array(pg_temp.new_post(304,-10,'cash-consumption-booked','65000000-0000-4000-8000-000000000101','cashTransfer')))$$,'P0001','ordinary_investment_invalid_posting','internal transfer cannot omit destination allocation');
select lives_ok($$select pg_temp.atomic_group(pg_temp.new_parent(304,'65000000-0000-4000-8000-000000000101',10,'65000000-0000-4000-8000-000000000102'),jsonb_build_array(pg_temp.new_post(304,-10,'cash-consumption-booked','65000000-0000-4000-8000-000000000101','cashTransfer'),pg_temp.new_post(304,10,'cash-destination-booked','65000000-0000-4000-8000-000000000102','cashTransfer')))$$,'same-currency internal transfer publishes exact canonical pair');
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000102'),10::bigint,'transfer credits actual destination10');
select lives_ok($$select pg_temp.atomic_group(pg_temp.new_parent(305,'65000000-0000-4000-8000-000000000102'),jsonb_build_array(pg_temp.new_post(305,-10,'cash-consumption-booked','65000000-0000-4000-8000-000000000102')))$$,'later destination expense consumes transferred booked money');
select throws_ok($$select pg_temp.atomic_group((select to_jsonb(r)||'{"deleted_at":"2026-10-28T02:00:00Z"}'::jsonb from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000304'),(select jsonb_agg(to_jsonb(r)||'{"deleted_at":"2026-10-28T02:00:00Z"}'::jsonb) from public.investment_wallet_postings r where event_id='65000000-0000-4000-8000-000000000304'))$$,'P0001','ordinary_investment_capacity_conflict','cannot delete transfer whose destination funds were consumed');
select ok((select deleted_at is null and sync_version=1 from public.ledger_transactions where id='65000000-0000-4000-8000-000000000304'),'failed net capacity keeps real transfer active and unchanged');
reset role;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values('65000000-0000-4000-8000-000000000103','65000000-0000-4000-8000-000000000001','Unreconciled holder','cash','banknote.fill','#111111','JPY',0);
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at)
values('65000000-0000-4000-8000-000000000210','65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000201','65000000-0000-4000-8000-000000000103','65000000-0000-4000-8000-000000000201','cashAccrual','unreconciled','derived',40,'JPY',40,'JPY','2026-10-28T00:01:00Z');
create function pg_temp.reserve_adjustment() returns jsonb language sql as $$
 select pg_temp.new_parent(306)||jsonb_build_object('id',public.investment_ledger_id('65000000-0000-4000-8000-000000000306','cash-unreconciled-adjustment'),'primary_kind_raw_value','transfer','transfer_subtype_raw_value','internalTransfer','settlement_role_raw_value','investmentReserveUse','source_wallet_id',public.investment_system_wallet_id('65000000-0000-4000-8000-000000000001'),'destination_wallet_id','65000000-0000-4000-8000-000000000103','amount_minor',20,'reporting_amount_minor',20,'destination_amount_minor',20,'destination_currency_code','JPY','reporting_expense_minor',0,'reporting_income_minor',0)
$$;
set local role authenticated;
select throws_ok($$select pg_temp.atomic_group(pg_temp.new_parent(306,'65000000-0000-4000-8000-000000000103',20),jsonb_build_array(pg_temp.new_post(306,-20,'cash-consumption-unreconciled','65000000-0000-4000-8000-000000000103','cashConsumption','unreconciled')))$$,'P0001','ordinary_investment_invalid_adjustment','unreconciled use requires actual reserve adjustment');
select lives_ok($$select pg_temp.atomic_group(pg_temp.new_parent(306,'65000000-0000-4000-8000-000000000103',20),jsonb_build_array(pg_temp.new_post(306,-20,'cash-consumption-unreconciled','65000000-0000-4000-8000-000000000103','cashConsumption','unreconciled')),pg_temp.reserve_adjustment())$$,'closed API derives authorized reserve use without widening ordinary RLS');
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000103'),0::bigint,'reserve adjustment offsets exactly the real expense');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000103' and deleted_at is null),20::bigint,'unreconciled bucket retains exact20');
select is((select sync_version from public.ledger_transactions where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000306','cash-unreconciled-adjustment')),1::bigint,'canonical reserve adjustment committed exactly once');
reset role;


create function pg_temp.reserve_lifecycle(is_delete boolean) returns jsonb language sql as $$
 select pg_temp.atomic_group(
 (select to_jsonb(r)||jsonb_build_object('deleted_at',case when is_delete then '2026-10-28T03:00:00Z' end) from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000306'),
 (select jsonb_agg(to_jsonb(r)||jsonb_build_object('deleted_at',case when is_delete then '2026-10-28T03:00:00Z' end)) from public.investment_wallet_postings r where event_id='65000000-0000-4000-8000-000000000306'),
 (select to_jsonb(r)||jsonb_build_object('deleted_at',case when is_delete then '2026-10-28T03:00:00Z' end) from public.ledger_transactions r where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000306','cash-unreconciled-adjustment')))
$$;
set local role authenticated;
select lives_ok($$select pg_temp.reserve_lifecycle(true)$$,'unreconciled deletion retires primary, reserve and allocation atomically');
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000103'),0::bigint,'reserve reversal and expense reversal preserve actual zero');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000103' and deleted_at is null),40::bigint,'unreconciled deletion returns original40');
select lives_ok($$select pg_temp.reserve_lifecycle(false)$$,'unreconciled restore publishes all three rows');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000103' and deleted_at is null),20::bigint,'unreconciled restore consumes exactly20');
select throws_ok($$select pg_temp.atomic_group(pg_temp.new_parent(303),jsonb_build_array(pg_temp.new_post(303)))$$,'P0001','ordinary_investment_version_conflict','base zero never overwrites a same-owner existing event');
select throws_ok($$select public.mutate_ordinary_investment_event(pg_temp.new_parent(307),null,jsonb_build_array(pg_temp.new_post(307)),0,0,'{}',pg_temp.expected_presence(pg_temp.new_parent(307),jsonb_build_array(pg_temp.new_post(307))))$$,'P0001','ordinary_investment_incomplete_group','expected version map must be complete');
select throws_ok($$select public.mutate_ordinary_investment_event(pg_temp.new_parent(307),null,jsonb_build_array(pg_temp.new_post(307)),0,0,jsonb_build_object(public.investment_ledger_id('65000000-0000-4000-8000-000000000307','cash-consumption-booked'),'0'),pg_temp.expected_presence(pg_temp.new_parent(307),jsonb_build_array(pg_temp.new_post(307))))$$,'P0001','ordinary_investment_invalid_posting','posting versions cannot be coerced from strings');
select throws_ok($$select pg_temp.atomic_group(pg_temp.new_parent(307),jsonb_build_array(pg_temp.new_post(307),pg_temp.new_post(307)))$$,'P0001','ordinary_investment_incomplete_group','duplicate canonical components cannot spend twice');
select throws_ok($$select pg_temp.atomic_group((select to_jsonb(r) from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000304'),(select jsonb_build_array(to_jsonb(r)) from public.investment_wallet_postings r where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000304','cash-consumption-booked')))$$,'P0001','ordinary_investment_incomplete_group','editing cannot omit an existing destination component');
create temporary table ordinary_permission_proposal as select pg_temp.new_parent(307) t,jsonb_build_array(pg_temp.new_post(307)) p;
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000002',true);
select throws_ok($$select pg_temp.atomic_group(t,p) from ordinary_permission_proposal$$,'P0001','ordinary_investment_permission_required','another actor without investment permission cannot mutate owner group');
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select pg_temp.atomic_group(t,p) from ordinary_permission_proposal$$,'P0001','ordinary_investment_authentication_required','empty authenticated subject grants no authority');
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000001',true);
select is((select count(*) from public.ledger_transactions where id='65000000-0000-4000-8000-000000000307'),0::bigint,'rejected groups have no partial parent');
reset role;


-- Zero is a real observed legacy version; it is not an absence capability.
insert into public.ledger_transactions select (jsonb_populate_record(null::public.ledger_transactions,pg_temp.new_parent(308,'65000000-0000-4000-8000-000000000101',3))).*;
insert into public.investment_wallet_postings select (jsonb_populate_record(null::public.investment_wallet_postings,pg_temp.new_post(308,-3))).*;
create function pg_temp.update_zero() returns jsonb language sql as $$
 select pg_temp.atomic_group(
 (select to_jsonb(r)||'{"amount_minor":4,"reporting_amount_minor":4}'::jsonb from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000308'),
 (select jsonb_build_array(to_jsonb(r)||'{"amount_minor":-4,"accounting_amount_minor":-4}'::jsonb) from public.investment_wallet_postings r where event_id='65000000-0000-4000-8000-000000000308'))
$$;
create function pg_temp.zero_with_presence(flags jsonb) returns jsonb language sql as $$
 select public.mutate_ordinary_investment_event(
 (select to_jsonb(r)||'{"amount_minor":4,"reporting_amount_minor":4}'::jsonb from public.ledger_transactions r where id='65000000-0000-4000-8000-000000000308'),null,
 (select jsonb_build_array(to_jsonb(r)||'{"amount_minor":-4,"accounting_amount_minor":-4}'::jsonb) from public.investment_wallet_postings r where event_id='65000000-0000-4000-8000-000000000308'),0,0,
 jsonb_build_object(public.investment_ledger_id('65000000-0000-4000-8000-000000000308','cash-consumption-booked'),0),flags)
$$;
set local role authenticated;
select throws_ok($$select pg_temp.zero_with_presence('{}')$$,'P0001','ordinary_investment_invalid_presence','presence map cannot omit compared identities');
select throws_ok($$select pg_temp.zero_with_presence(jsonb_build_object('65000000-0000-4000-8000-000000000308',false,public.investment_ledger_id('65000000-0000-4000-8000-000000000308','cash-consumption-booked'),false))$$,'P0001','ordinary_investment_version_conflict','absent-zero capability cannot overwrite observed-zero identities');
select throws_ok($$select pg_temp.zero_with_presence(jsonb_build_object('65000000-0000-4000-8000-000000000308','true',public.investment_ledger_id('65000000-0000-4000-8000-000000000308','cash-consumption-booked'),true))$$,'P0001','ordinary_investment_invalid_presence','presence booleans cannot be coerced from strings');
select throws_ok($$select public.mutate_ordinary_investment_event(pg_temp.new_parent(309),null,jsonb_build_array(pg_temp.new_post(309)),0,0,jsonb_build_object(public.investment_ledger_id('65000000-0000-4000-8000-000000000309','cash-consumption-booked'),0),jsonb_build_object('65000000-0000-4000-8000-000000000309',true,public.investment_ledger_id('65000000-0000-4000-8000-000000000309','cash-consumption-booked'),true))$$,'P0001','ordinary_investment_version_conflict','expected-existing zero cannot create an absent group');
select is((select count(*) from public.ledger_transactions where id='65000000-0000-4000-8000-000000000309'),0::bigint,'expected-presence mismatch leaves no partial parent');
select is((select sync_version from public.ledger_transactions where id='65000000-0000-4000-8000-000000000308'),0::bigint,'failed absent and malformed comparisons preserve observed-zero parent');
select lives_ok($$select pg_temp.update_zero()$$,'observed version-zero parent and allocation are updated together');
select is((select sync_version from public.ledger_transactions where id='65000000-0000-4000-8000-000000000308'),1::bigint,'observed zero parent advances to1');
select is((select sync_version from public.investment_wallet_postings where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000308','cash-consumption-booked')),1::bigint,'observed zero posting advances to1');
select is((select amount_minor from public.ledger_transactions where id='65000000-0000-4000-8000-000000000308'),4::bigint,'observed zero financial edit is retained');
reset role;

-- Cross-event capacity is global to the owned holder/bucket. The earlier
-- new event must wait until another compared event releases its old reservation.
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values('65000000-0000-4000-8000-000000000104','65000000-0000-4000-8000-000000000001','Capacity sequence','cash','banknote.fill','#111111','JPY',40);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values('65000000-0000-4000-8000-000000000211','65000000-0000-4000-8000-000000000001','income','posted','Imported booked income for sequence',60,'2026-10-28T00:00:00Z','65000000-0000-4000-8000-000000000104','JPY','JPY',60,'65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000001');
insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at,sync_version)
values('65000000-0000-4000-8000-000000000212','65000000-0000-4000-8000-000000000001','65000000-0000-4000-8000-000000000211','65000000-0000-4000-8000-000000000104','65000000-0000-4000-8000-000000000211','cashAccrual','booked','derived',60,'JPY',60,'JPY','2026-10-28T00:00:00Z',1);
create function pg_temp.capacity_event(n integer,p_amount bigint,p_used bigint) returns jsonb language plpgsql as $$
declare event uuid:=('65000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;t jsonb;p jsonb;occurred text;
begin
 occurred:=case when n=322 then '2026-10-28T00:59:30Z' else '2026-10-28T01:00:00Z' end;
 select to_jsonb(r) into t from public.ledger_transactions r where r.id=event;
 select to_jsonb(r) into p from public.investment_wallet_postings r where r.id=public.investment_ledger_id(event,'cash-consumption-booked');
 t:=coalesce(t,pg_temp.new_parent(n,'65000000-0000-4000-8000-000000000104',p_amount))||jsonb_build_object('amount_minor',p_amount,'reporting_amount_minor',p_amount,'occurred_at',occurred);
 p:=coalesce(p,pg_temp.new_post(n,p_used,'cash-consumption-booked','65000000-0000-4000-8000-000000000104'))||jsonb_build_object('amount_minor',p_used,'accounting_amount_minor',p_used,'occurred_at',occurred);
 return pg_temp.atomic_group(t,jsonb_build_array(p));
end $$;
set local role authenticated;
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000104'),100::bigint,'sequence starts with actual100 and booked60');
select lives_ok($$select pg_temp.capacity_event(320,70,-30)$$,'first real70 expense reserves booked30');
select lives_ok($$select pg_temp.capacity_event(321,20,-20)$$,'second real20 expense reserves booked20');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000104' and deleted_at is null),10::bigint,'only booked10 remains before release');
select throws_ok($$select pg_temp.capacity_event(322,60,-20)$$,'P0001','ordinary_investment_capacity_conflict','new earlier event cannot consume20 before existing allocation releases10');
select is((select count(*) from public.ledger_transactions where id='65000000-0000-4000-8000-000000000322'),0::bigint,'failed capacity creates no partial primary');
select is((select count(*) from public.investment_wallet_postings where event_id='65000000-0000-4000-8000-000000000322'),0::bigint,'failed capacity creates no partial allocation');
select is((select sync_version from public.ledger_transactions where id='65000000-0000-4000-8000-000000000320'),1::bigint,'failed new event cannot alter an existing event version');
select lives_ok($$select pg_temp.capacity_event(320,20,-20)$$,'compared edit releases10 from the first event without waiting for the failed event');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000104' and deleted_at is null),20::bigint,'release exposes booked20 for the earlier retry');
select lives_ok($$select pg_temp.capacity_event(322,60,-20)$$,'same new event succeeds after capacity release');
select is((select current_balance_minor from public.ledger_wallets where id='65000000-0000-4000-8000-000000000104'),0::bigint,'complete sequence spends exact actual100');
select is((select sum(accounting_amount_minor)::bigint from public.investment_wallet_postings where wallet_id='65000000-0000-4000-8000-000000000104' and deleted_at is null),0::bigint,'three allocations consume exact booked60 without negative or duplicate cash');
select ok((select amount_minor=20 and sync_version=1 from public.ledger_transactions where id='65000000-0000-4000-8000-000000000321'),'unrelated second event remains unchanged');
select ok((select accounting_amount_minor=-20 and sync_version=1 from public.investment_wallet_postings where id=public.investment_ledger_id('65000000-0000-4000-8000-000000000322','cash-consumption-booked')),'retry inserts its canonical allocation once');
reset role;

select * from finish();
rollback;
