#!/usr/bin/env python3
"""Real local authenticated marker races, scoped to disposable fixture IDs only."""
import argparse,json,pathlib,re,shutil,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
OWNER='68000000-0000-4000-8000-000000000001'
OTHER='68000000-0000-4000-8000-000000000002'
EVENT='68000000-0000-4000-8000-000000000401'
SCHEMA='mistia_installment_paid_cycle_race_test'
PREFIX='mistia_installment_paid_race_'
CASES=['foreign_identity','sibling_first','sibling_after','source_delete_late']
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--case',choices=CASES);args=ap.parse_args()
    docker=shutil.which('docker') or '/usr/local/bin/docker'
    project=re.search(r'^project_id\s*=\s*"([a-z0-9_-]+)"',(ROOT/'supabase/config.toml').read_text(),re.M).group(1)
    assert subprocess.check_output([docker,'context','inspect','--format','{{.Endpoints.docker.Host}}'],text=True).strip().startswith('unix://')
    container='supabase_db_'+project
    def ports():
        r=json.loads(subprocess.check_output([docker,'inspect',container],text=True))[0];assert r['State']['Running']
        for group in [r['HostConfig'].get('PortBindings'),r['NetworkSettings'].get('Ports')]:
            assert group and all(p['HostIp']=='127.0.0.1' for ps in group.values() for p in ps or [])
    ports();command=[docker,'exec','-i',container,'psql','-X','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1']
    def sql(text):
        p=subprocess.run(command,input="set statement_timeout='12s';"+text,capture_output=True,text=True,timeout=15)
        assert p.returncode==0,p.stderr;return p.stdout.strip()
    def auth(owner):return f"set role authenticated;select set_config('request.jwt.claim.sub','{owner}',false);select set_config('request.jwt.claim.role','authenticated',false);"
    def launch(text,name):
        p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        p.stdin.write(f"set statement_timeout='12s';set application_name='{PREFIX+name}';"+text);p.stdin.close();return p
    def lock_pid(key):
        value=sql(f"select pid from pg_locks where locktype='advisory' and classid=0 and objid={key} and objsubid=1 and granted;")
        return int(value.splitlines()[-1]) if value.splitlines()[-1:] and value.splitlines()[-1].isdigit() else None
    def barrier(key):
        end=time.monotonic()+8
        while time.monotonic()<end:
            pid=lock_pid(key)
            if pid:return pid
            time.sleep(.1)
        raise AssertionError('Test barrier not reached')
    def waiting(name,p):
        end=time.monotonic()+5
        while time.monotonic()<end:
            if p.poll() is not None:return False
            value=sql(f"select count(*) from pg_stat_activity where application_name='{PREFIX+name}' and wait_event_type='Lock';")
            if value.splitlines()[-1]=='1':return True
            time.sleep(.1)
        return False
    def lit(value):return "'"+json.dumps(value).replace("'","''")+"'::jsonb"
    assert sql(f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}');").splitlines()[-1]=='0'
    assert sql(f"select count(*) from pg_namespace where nspname='{SCHEMA}';").splitlines()[-1]=='0'
    assert sql(f"select count(*) from pg_stat_activity where application_name like '{PREFIX}%';").splitlines()[-1]=='0'
    setup=False;outcomes=[]
    try:
        fixture=(ROOT/'supabase/tests/database/installment_paid_cycle_publication.sql').read_text().split("select pg_temp.capture('initial');",1)[0]
        fixture=fixture.replace('select no_plan();','').replace('67000000','68000000')
        foreign=f"""reset role;
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values ('{OTHER}','authenticated','authenticated','other-installment-race@mistia.test','',now(),'{{"provider":"email"}}','{{}}',now(),now());
insert into public.user_profiles(user_id,display_name) values('{OTHER}','Other caller') on conflict(user_id) do nothing;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor) values('68000000-0000-4000-8000-000000000103','{OTHER}','Other','cash','banknote.fill','#111111','JPY',1000);
insert into public.installment_plans(id,user_id,name,icon_symbol_name,amount_per_cycle_minor,due_day,frequency_months,payment_wallet_id,currency_code) values('68000000-0000-4000-8000-000000000203','{OTHER}','Other plan','mistia.plan.installment',75,28,1,'68000000-0000-4000-8000-000000000103','JPY');
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,created_by_user_id,last_modified_by_user_id) values('68000000-0000-4000-8000-000000000901','{OTHER}','expense','posted','Other payment',75,'2026-10-28T00:01:00Z','68000000-0000-4000-8000-000000000103','JPY','{OTHER}','{OTHER}');
"""
        raw=sql(fixture+foreign+"select pg_temp.capture('initial');select encode(convert_to(jsonb_build_object('cycle',pg_temp.cycle_payload(),'proof',(select to_jsonb(saved_proof) from proof saved_proof where name='initial'))::text,'UTF8'),'hex');commit;")
        setup=True;packet=json.loads(bytes.fromhex(next(l for l in raw.splitlines() if re.fullmatch(r'7b[0-9a-f]+',l))).decode())
        c=packet['cycle'];proof=packet['proof']
        rpc=auth(OWNER)+f"select public.mutate_installment_paid_cycle({lit(c)},0,false,{lit(proof['p'])},{lit(proof['l'])},{lit(proof['w'])},{lit(proof['s'])});"
        def insert(row):
            return "insert into public.due_occurrence_records select (jsonb_populate_record(null::public.due_occurrence_records,"+lit(row)+")).*;"
        for index,case in enumerate([args.case] if args.case else CASES):
            # Cleanup updates parent audit stamps, so every independent race
            # captures fresh real parent/ledger/wallet comparison observations.
            proof=json.loads(sql("select jsonb_build_object('p',(select to_jsonb(r) from public.installment_plans r where id='68000000-0000-4000-8000-000000000201'),'l',(select to_jsonb(r) from public.ledger_transactions r where id='68000000-0000-4000-8000-000000000301'),'w',(select to_jsonb(r) from public.ledger_wallets r where id='68000000-0000-4000-8000-000000000101'),'s','[]'::jsonb);").splitlines()[-1])
            rpc=auth(OWNER)+f"select public.mutate_installment_paid_cycle({lit(c)},0,false,{lit(proof['p'])},{lit(proof['l'])},{lit(proof['w'])},{lit(proof['s'])});"
            release=166501+index*2;arrived=release+1;assert not lock_pid(release) and not lock_pid(arrived)
            gate=first=second=None;gate_pid=None
            try:
                pause_id='68000000-0000-4000-8000-000000000402' if case=='sibling_first' else EVENT
                device='68000000-0000-4000-8000-000000000902' if case=='sibling_first' else c['last_modified_by_device_id']
                sql(f"create schema {SCHEMA};create function {SCHEMA}.pause_marker() returns trigger language plpgsql as $$begin if new.id='{pause_id}' and new.user_id='{OWNER}' and new.last_modified_by_device_id='{device}' then perform pg_advisory_xact_lock({arrived});perform pg_advisory_xact_lock({release});end if;return new;end;$$;create trigger z_mistia_installment_paid_race before insert on public.due_occurrence_records for each row execute function {SCHEMA}.pause_marker();")
                gate=launch(f'select pg_advisory_lock({release});select pg_sleep(11);','gate');gate_pid=barrier(release)
                sibling=dict(c,id='68000000-0000-4000-8000-000000000402',linked_transaction_id='68000000-0000-4000-8000-000000000302',last_modified_by_device_id='68000000-0000-4000-8000-000000000902')
                if case=='sibling_first':
                    first=launch(auth(OWNER)+insert(sibling),'first');barrier(arrived)
                    second=launch(rpc,'second');blocked=waiting('second',second)
                else:
                    first=launch(rpc,'first');barrier(arrived)
                    if case=='foreign_identity':
                        contender=dict(c,user_id=OTHER,source_id='68000000-0000-4000-8000-000000000203',linked_transaction_id='68000000-0000-4000-8000-000000000901',amount_minor_snapshot=75,last_modified_by_device_id='68000000-0000-4000-8000-000000000902')
                        sql(auth(OTHER)+insert(contender));blocked=True
                    elif case=='sibling_after':
                        second=launch(auth(OWNER)+insert(sibling),'second');blocked=waiting('second',second)
                    else:
                        second=launch(auth(OWNER)+"update public.installment_plans set deleted_at='2026-10-28T00:05:00Z',sync_version=2 where id='68000000-0000-4000-8000-000000000201';",'second');blocked=waiting('second',second)
                sql(f'select pg_terminate_backend({gate_pid});');gate_pid=None
                for p in [first,second]:
                    if p:p.wait(timeout=12)
                err1=first.stderr.read();err2=second.stderr.read() if second else ''
                if case=='foreign_identity':
                    actual=sql(f"select user_id,source_id,linked_transaction_id,amount_minor_snapshot,sync_version from public.due_occurrence_records where id='{EVENT}';").splitlines()[-1]
                    ok=first.returncode!=0 and 'installment_payment_version_conflict' in err1 and actual==f'{OTHER}|68000000-0000-4000-8000-000000000203|68000000-0000-4000-8000-000000000901|75|1'
                elif case=='sibling_first':
                    ok=blocked and first.returncode==0 and second.returncode!=0 and 'installment_payment_membership_changed' in err2 and sql(f"select count(*) from public.due_occurrence_records where id='{EVENT}';").splitlines()[-1]=='0'
                else:
                    ok=blocked and first.returncode==second.returncode==0
                    if case=='source_delete_late':
                        ok=ok and sql("select deleted_at is not null from public.installment_plans where id='68000000-0000-4000-8000-000000000201';").splitlines()[-1]=='t'
                outcomes.append(ok);print(('PASS: ' if ok else 'FAIL: ')+case+'; compared winner/source preserved, contender serialization='+str(blocked),flush=True)
                if not ok:print('Diagnostic exits '+str((first.returncode,second.returncode if second else None))+' errors '+err1[-300:]+err2[-300:],flush=True)
            finally:
                if gate_pid:sql(f'select pg_terminate_backend({gate_pid});')
                for p in [first,second,gate]:
                    if p:
                        try:p.wait(timeout=12)
                        except subprocess.TimeoutExpired:p.kill();p.wait()
                sql(f"drop trigger if exists z_mistia_installment_paid_race on public.due_occurrence_records;drop schema if exists {SCHEMA} cascade;delete from public.due_occurrence_records where user_id in ('{OWNER}','{OTHER}');update public.installment_plans set deleted_at=null,sync_version=1 where id='68000000-0000-4000-8000-000000000201';")
        assert all(outcomes),'Actual installment paid-cycle concurrency invariant failed'
    finally:
        if setup:
            sql(f"drop trigger if exists z_mistia_installment_paid_race on public.due_occurrence_records;drop schema if exists {SCHEMA} cascade;delete from auth.users where id in ('{OWNER}','{OTHER}');")
            assert sql(f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}');").splitlines()[-1]=='0'
        ports()
if __name__=='__main__':main()
