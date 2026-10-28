#!/usr/bin/env python3
"""Two authenticated callers collide with an absent ordinary parent/reserve/posting.

Local project Docker socket and explicit loopback bindings only. All fixture IDs,
barriers and temporary schema are owned by this test and removed atomically.
The same-owner zero-version contender uses the real ordinary ledger insert policy;
cash postings have no authenticated direct-insert policy and are RPC-only.
"""
import json
import pathlib
import re
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
OWNER = '66000000-0000-4000-8000-000000000001'
OTHER = '66000000-0000-4000-8000-000000000002'
FOREIGN_WALLET = '66000000-0000-4000-8000-000000000103'
FOREIGN_LEDGER = '66000000-0000-4000-8000-000000000901'
OWN_WALLET = '66000000-0000-4000-8000-000000000104'
SCHEMA = 'mistia_ordinary_event_scope_race_test'


def main():
    docker = shutil.which('docker') or '/usr/local/bin/docker'
    project = re.search(r'^project_id\s*=\s*"([a-z0-9_-]+)"', (ROOT/'supabase/config.toml').read_text(), re.M).group(1)
    endpoint = subprocess.check_output([docker, 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], text=True).strip()
    assert endpoint.startswith('unix://')
    container = 'supabase_db_'+project
    state = json.loads(subprocess.check_output([docker, 'inspect', container], text=True))[0]
    assert state['State']['Running']
    for group in [state['HostConfig'].get('PortBindings'), state['NetworkSettings'].get('Ports')]:
        assert group and all(p['HostIp']=='127.0.0.1' for ps in group.values() for p in (ps or []))
    command = [docker,'exec','-i',container,'psql','-X','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1']

    def sql(text):
        p = subprocess.run(command,input=text,capture_output=True,text=True,timeout=15)
        assert p.returncode==0,p.stderr.strip()
        return p.stdout.strip()

    def launch(text):
        p = subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        p.stdin.write(text);p.stdin.close()
        return p

    def lock_pid(key):
        v=sql(f"select pid from pg_locks where locktype='advisory' and classid=0 and objid={key} and objsubid=1 and granted;")
        return int(v) if v else None

    def wait_for_lock(key):
        end=time.monotonic()+10
        while time.monotonic()<end:
            pid=lock_pid(key)
            if pid:return pid
            time.sleep(.1)
        raise AssertionError('Ordinary event scope race did not reach its barrier')

    def auth(owner):
        return f"set role authenticated;select set_config('request.jwt.claim.sub','{owner}',false);select set_config('request.jwt.claim.role','authenticated',false);"

    def expense(identity,owner=OTHER,wallet=FOREIGN_WALLET,version=1):
        return f"insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id,sync_version) values ('{identity}','{owner}','expense','posted','Other caller expense',75,'2026-10-27T00:00:00Z','{wallet}','JPY','JPY',75,'{owner}','{owner}',{version}) returning id;"

    assert sql(f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}');")=='0','Fixture exists; nothing changed'
    assert sql(f"select count(*) from pg_namespace where nspname='{SCHEMA}';")=='0'
    for key in range(164301,164309):assert not lock_pid(key)
    setup=False;outcomes=[]
    try:
        fixture=(ROOT/'supabase/tests/database/investment_ordinary_allocation_publication.sql').read_text().split("select is((select current_balance_minor",1)[0]
        fixture=fixture.replace('65000000','66000000').replace('select no_plan();','')
        other=f"insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values ('{OTHER}','authenticated','authenticated','ordinary-race-other@mistia.test','',now(),'{{\"provider\":\"email\",\"providers\":[\"email\"]}}','{{}}',now(),now());insert into public.user_profiles(user_id,display_name) values ('{OTHER}','Other caller') on conflict(user_id) do nothing;insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor) values ('{FOREIGN_WALLET}','{OTHER}','Other caller wallet','cash','banknote.fill','#111111','JPY',10000);"
        own_wallet=f"insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor) values ('{OWN_WALLET}','{OWNER}','Other source','cash','banknote.fill','#111111','JPY',10000);"
        seed=f"insert into public.investment_wallet_postings(id,user_id,event_id,wallet_id,ledger_transaction_id,role_raw_value,cash_bucket_raw_value,cash_origin_raw_value,amount_minor,currency_code,accounting_amount_minor,accounting_currency_code,occurred_at) values ('66000000-0000-4000-8000-000000000203','{OWNER}','66000000-0000-4000-8000-000000000201','66000000-0000-4000-8000-000000000101','66000000-0000-4000-8000-000000000201','cashAccrual','unreconciled','derived',60,'JPY',60,'JPY','2026-10-28T00:00:00Z');"
        raw=sql(fixture+other+own_wallet+expense(FOREIGN_LEDGER)+seed+"select encode(convert_to(jsonb_build_object('transaction',(select to_jsonb(t) from public.ledger_transactions t where id='66000000-0000-4000-8000-000000000301'),'posting',pg_temp.consumption('66000000-0000-4000-8000-000000000501',-10))::text,'UTF8'),'hex');commit;")
        setup=True
        proposal=json.loads(bytes.fromhex(next(l for l in raw.splitlines() if re.fullmatch(r'7b[0-9a-f]+',l))).decode())
        for index,kind in enumerate(['ledger','posting','adjustment','own_ledger_zero']):
            event=f'66000000-0000-4000-8000-00000000050{index+1}'
            posting=sql(f"select public.investment_ledger_id('{event}','cash-consumption-{'unreconciled' if kind=='adjustment' else 'booked'}');")
            adjustment=sql(f"select public.investment_ledger_id('{event}','cash-unreconciled-adjustment');")
            is_own=kind.startswith('own_');is_ledger=kind in ('ledger','adjustment','own_ledger_zero')
            winner_owner=OWNER if is_own else OTHER;winner_wallet=OWN_WALLET if is_own else FOREIGN_WALLET;winner_ledger=FOREIGN_LEDGER;winner_version=0 if is_own else 1
            target=adjustment if kind=='adjustment' else event if is_ledger else posting
            table='ledger_transactions' if is_ledger else 'investment_wallet_postings'
            release=164301+index*2;arrived=release+1
            gate=contender=None;gate_pid=None
            try:
                sql(f"create schema {SCHEMA};create function {SCHEMA}.wait_after_absence() returns trigger language plpgsql as $$begin if new.id='{target}' and new.user_id='{OWNER}' and new.last_modified_by_device_id='66000000-0000-4000-8000-000000000901' then perform pg_advisory_xact_lock({arrived});perform pg_advisory_xact_lock({release});end if;return new;end;$$;create trigger mistia_ordinary_event_scope_race before insert on public.{table} for each row execute function {SCHEMA}.wait_after_absence();")
                gate=launch(f'select pg_advisory_lock({release});select pg_sleep(30);');gate_pid=wait_for_lock(release)
                proposed=dict(proposal['transaction'],id=event,sync_version=0,amount_minor=10,reporting_amount_minor=10,last_modified_by_device_id='66000000-0000-4000-8000-000000000901')
                posting_row=dict(proposal['posting'],id=posting,event_id=event,ledger_transaction_id=event,sync_version=0)
                adjustment_row=None
                if kind=='adjustment':
                    posting_row['cash_bucket_raw_value']='unreconciled'
                    root=sql(f"select public.investment_system_wallet_id('{OWNER}');")
                    adjustment_row=dict(proposed,id=adjustment,primary_kind_raw_value='transfer',transfer_subtype_raw_value='internalTransfer',settlement_role_raw_value='investmentReserveUse',source_wallet_id=root,destination_wallet_id=proposed['source_wallet_id'],destination_currency_code='JPY',destination_amount_minor=10,reporting_expense_minor=0,reporting_income_minor=0)
                adjustment_arg="null" if adjustment_row is None else "'"+json.dumps(adjustment_row)+"'::jsonb"
                presence={event:False,posting:False}
                if adjustment_row is not None:presence[adjustment]=False
                contender=launch(auth(OWNER)+f"select public.mutate_ordinary_investment_event('{json.dumps(proposed)}'::jsonb,{adjustment_arg},'{json.dumps([posting_row])}'::jsonb,0,0,'{json.dumps({posting:0})}'::jsonb,'{json.dumps(presence)}'::jsonb);")
                wait_for_lock(arrived)
                if is_ledger:
                    winner=sql(auth(winner_owner)+expense(target,winner_owner,winner_wallet,winner_version));assert winner.splitlines()[-2]==target,winner
                else:
                    foreign={'id':posting,'user_id':winner_owner,'event_id':winner_ledger,'wallet_id':winner_wallet,'ledger_transaction_id':winner_ledger,'role_raw_value':'cashCorrection','cash_bucket_raw_value':'booked','cash_origin_raw_value':'manual','amount_minor':25,'accounting_amount_minor':25,'currency_code':'JPY','accounting_currency_code':'JPY','occurred_at':'2026-10-27T00:00:00Z','created_at':'2026-10-27T00:00:00Z','updated_at':'2026-10-27T00:00:00Z','deleted_at':None,'last_modified_by_device_id':'66000000-0000-4000-8000-000000000902'}
                    winner=sql(auth(winner_owner)+f"select (public.mutate_investment_cash_posting('{json.dumps(foreign)}'::jsonb,0,false)).id;");assert winner.splitlines()[-1]==posting
                assert sql(f'select pg_terminate_backend({gate_pid});')=='t';gate_pid=None
                contender.wait(timeout=10);error=contender.stderr.read()
                if is_ledger:
                    actual=sql(f"select user_id,source_wallet_id,amount_minor,sync_version from public.ledger_transactions where id='{target}';")
                    intact=actual==f'{winner_owner}|{winner_wallet}|75|{winner_version}'
                    no_partial=sql(f"select count(*) from public.investment_wallet_postings where id='{posting}';")=='0'
                    code='ordinary_investment_version_conflict'
                    if kind=='adjustment':no_partial=no_partial and sql(f"select count(*) from public.ledger_transactions where id='{event}';")=='0'
                else:
                    actual=sql(f"select user_id,wallet_id,ledger_transaction_id,accounting_amount_minor,sync_version from public.investment_wallet_postings where id='{posting}';")
                    intact=actual==f'{winner_owner}|{winner_wallet}|{winner_ledger}|25|{winner_version}'
                    no_partial=sql(f"select count(*) from public.ledger_transactions where id='{event}';")=='0'
                    code='ordinary_investment_version_conflict'
                ok=contender.returncode!=0 and code in error and intact and no_partial
                outcomes.append(ok)
                print(('PASS: ' if ok else 'FAIL: ')+kind+' absent-row ordinary event race; compared winner='+actual+'; no partial caller result='+str(no_partial),flush=True)
            finally:
                if gate_pid:sql(f'select pg_terminate_backend({gate_pid});')
                for p in [contender,gate]:
                    if p:
                        try:p.wait(timeout=10)
                        except subprocess.TimeoutExpired:p.kill();p.wait()
                sql(f"drop trigger if exists mistia_ordinary_event_scope_race on public.{table};drop schema if exists {SCHEMA} cascade;delete from public.investment_wallet_postings where id='{posting}' and user_id in ('{OWNER}','{OTHER}');delete from public.ledger_transactions where id in ('{event}','{adjustment}') and user_id in ('{OWNER}','{OTHER}');")
                assert not lock_pid(release) and not lock_pid(arrived)
        assert all(outcomes),'An absent-row ordinary event contender overwrote or partially persisted a compared winner'
    finally:
        if setup:
            sql(f"begin;drop trigger if exists mistia_ordinary_event_scope_race on public.ledger_transactions;drop trigger if exists mistia_ordinary_event_scope_race on public.investment_wallet_postings;drop schema if exists {SCHEMA} cascade;delete from public.investment_wallet_postings where user_id in ('{OWNER}','{OTHER}');delete from public.investment_trades where user_id in ('{OWNER}','{OTHER}');delete from public.investment_assets where user_id in ('{OWNER}','{OTHER}');delete from public.investment_channels where user_id in ('{OWNER}','{OTHER}');delete from public.ledger_transactions where user_id in ('{OWNER}','{OTHER}');alter table public.ledger_wallets disable trigger ledger_wallets_enforce_investment_system_wallet;delete from public.ledger_wallets where user_id in ('{OWNER}','{OTHER}');alter table public.ledger_wallets enable trigger ledger_wallets_enforce_investment_system_wallet;delete from auth.users where id in ('{OWNER}','{OTHER}');commit;")
            assert sql(f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}');")=='0'
        for key in range(164301,164309):assert not lock_pid(key)


if __name__=='__main__':main()
