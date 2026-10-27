begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

-- Synthetic, transaction-local owner. No service connection or production data.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('54000000-0000-4000-8000-000000000001','authenticated','authenticated','trade-publication@mistia.test','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('54000000-0000-4000-8000-000000000001','Trade publication fixture') on conflict(user_id) do nothing;
select set_config('request.jwt.claim.sub','54000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor,system_purpose_raw_value)
values (public.investment_system_wallet_id('54000000-0000-4000-8000-000000000001'),'54000000-0000-4000-8000-000000000001','Investment','investment','chart.line.uptrend.xyaxis','#9A67FF','JPY',0,'investmentProfit');
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('54000000-0000-4000-8000-000000000101','54000000-0000-4000-8000-000000000001','Funding','cash','banknote.fill','#111111','JPY',100000);
insert into public.investment_channels(id,user_id,name) values
('54000000-0000-4000-8000-000000000201','54000000-0000-4000-8000-000000000001','First channel'),
('54000000-0000-4000-8000-000000000202','54000000-0000-4000-8000-000000000001','Second channel');
insert into public.investment_assets(id,user_id,channel_id,name,currency_code,default_unit_label) values
('54000000-0000-4000-8000-000000000301','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000201','First asset','JPY','box'),
('54000000-0000-4000-8000-000000000302','54000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000202','Second asset','JPY','card');

create function pg_temp.proposal(p_id uuid,p_amount bigint default 100,p_date text default '2026-10-20T00:00:00Z') returns jsonb language sql as $$
select jsonb_build_object('id',p_id,'user_id','54000000-0000-4000-8000-000000000001','channel_id','54000000-0000-4000-8000-000000000201',
'asset_id','54000000-0000-4000-8000-000000000301','kind_raw_value','buy','quantity_decimal_string','2','unit_label','box',
'gross_amount_minor',p_amount,'currency_code','JPY','accounting_gross_amount_minor',p_amount,'accounting_currency_code','JPY',
'funding_wallet_id',case when p_amount=0 then null else '54000000-0000-4000-8000-000000000101' end,'capital_return_wallet_id',null,
'exchange_rate_decimal_string',null,'funding_to_accounting_rate_decimal_string',null,'accounting_to_capital_return_rate_decimal_string',null,
'note',null,'occurred_at',p_date,'created_at',p_date,'updated_at',p_date,'deleted_at',null,'sync_version',1,
'last_modified_by_device_id','54000000-0000-4000-8000-000000000901')
$$;
create temporary table reply on commit drop as select * from public.mutate_investment_trade(pg_temp.proposal('54000000-0000-4000-8000-000000000401'),0,false);
select is((select count(*) from reply),1::bigint,'create returns the requested active trade');
select is((select sync_version from reply),2::bigint,'new trade version advances again inside FIFO rebuild');
select is((select funding_ledger_transaction_id from reply),public.investment_ledger_id('54000000-0000-4000-8000-000000000401','funding'),'server creates the deterministic funding reference');
select is((select amount_minor from public.ledger_transactions where id=public.investment_ledger_id('54000000-0000-4000-8000-000000000401','funding')),100::bigint,'server creates the funding amount without an ordinary financial write');
select is((select current_balance_minor from public.ledger_wallets where id='54000000-0000-4000-8000-000000000101'),99900::bigint,'atomic RPC updates the real funding wallet');
select is((select position_cost_basis_after_minor from reply),100::bigint,'RPC returns rebuilt FIFO cost');
truncate reply;
insert into reply select * from public.mutate_investment_trade(pg_temp.proposal('54000000-0000-4000-8000-000000000402',40,'2026-10-21T00:00:00Z'),0,false);
select is((select count(*) from reply),2::bigint,'second create returns the entire active asset history');
select is((select sync_version from reply where id='54000000-0000-4000-8000-000000000401'),3::bigint,'other active trade versions also advance during rebuild');
select is((select sync_version from reply where id='54000000-0000-4000-8000-000000000402'),2::bigint,'newly created second trade has its own rebuilt version');
truncate reply;
insert into reply select * from public.mutate_investment_trade(pg_temp.proposal('54000000-0000-4000-8000-000000000401')||jsonb_build_object(
'asset_id','54000000-0000-4000-8000-000000000302','channel_id','54000000-0000-4000-8000-000000000202','unit_label',' card ','sync_version',4),3,false);
select is((select count(*) from reply),2::bigint,'cross-asset edit returns active original and destination histories');
select is((select count(distinct asset_id) from reply),2::bigint,'both affected assets are represented');
select is((select sync_version from reply where id='54000000-0000-4000-8000-000000000401'),5::bigint,'CAS proposal version advances once more during destination rebuild');
select is((select unit_label from reply where id='54000000-0000-4000-8000-000000000401'),'card','server normalizes the submitted unit label');
select is((select count(*) from public.mutate_investment_trade(pg_temp.proposal('54000000-0000-4000-8000-000000000402'),1,false)),0::bigint,'wrong compared version returns an empty CAS result without forcing');
select is((select sync_version from public.investment_trades where id='54000000-0000-4000-8000-000000000402'),3::bigint,'CAS miss leaves the current trade untouched');
truncate reply;
insert into reply select * from public.mutate_investment_trade(pg_temp.proposal('54000000-0000-4000-8000-000000000403',0,'2026-10-22T00:00:00Z'),0,false);
select is((select sync_version from reply where id='54000000-0000-4000-8000-000000000403'),2::bigint,'zero promotional buy also returns its rebuilt version');
select is((select funding_ledger_transaction_id from reply where id='54000000-0000-4000-8000-000000000403'),null::uuid,'promotional inventory creates no invented funding leg');
truncate reply;
insert into reply select * from public.delete_investment_trade('54000000-0000-4000-8000-000000000403','54000000-0000-4000-8000-000000000001',2,'2026-10-23T00:00:00Z','54000000-0000-4000-8000-000000000901');
select is((select count(*) from reply),1::bigint,'delete returns only its requested tombstone, not the rebuilt active history');
select is((select id from reply),'54000000-0000-4000-8000-000000000403'::uuid,'delete result keeps requested identity');
select ok((select deleted_at is not null from reply),'delete reply is a tombstone');
select is((select sync_version from reply),3::bigint,'deleted requested row advances once; it is excluded from active rebuild');
select is((select count(*) from public.investment_trades where asset_id='54000000-0000-4000-8000-000000000301' and deleted_at is null),1::bigint,'other asset history remains active after delete');
truncate reply;
insert into reply select * from public.mutate_investment_trade(pg_temp.proposal('54000000-0000-4000-8000-000000000402',40,'2026-10-21T00:00:00Z')||jsonb_build_object('sync_version',9007199254740993::bigint),5,false);
select is((select sync_version from reply where id='54000000-0000-4000-8000-000000000402'),9007199254740994::bigint,'RPC preserves a client proposal beyond IEEE754 and returns the rebuilt Int64 successor');
select is('2026-10-26T00:00:00.123456789Z'::timestamptz,'2026-10-26T00:00:00.123457Z'::timestamptz,'wire timestamps round to PostgreSQL microsecond precision');
select is('2026-10-26T00:00:00.999999600Z'::timestamptz,'2026-10-26T00:00:01Z'::timestamptz,'timestamp precision rounding can carry into the next second');
select is('2026-10-26T00:00:00.123456500Z'::timestamptz,'2026-10-26T00:00:00.123456Z'::timestamptz,'half-microsecond timestamp tie rounds to the even microsecond below');
select is('2026-10-26T00:00:00.123457500Z'::timestamptz,'2026-10-26T00:00:00.123458Z'::timestamptz,'half-microsecond timestamp tie rounds to the even microsecond above');
select * from finish();
rollback;
