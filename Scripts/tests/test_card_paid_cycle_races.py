#!/usr/bin/env python3
"""Actual authenticated card-marker commit boundaries on the disposable local DB."""
import argparse,json,pathlib,re,shutil,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
OWNER='72000000-0000-4000-8000-000000000001'
OTHER='72000000-0000-4000-8000-000000000002'
EVENT='72000000-0000-4000-8000-000000000401'
SCHEMA='mistia_card_paid_cycle_race_test'
PREFIX='mistia_card_paid_race_'
CASES=['foreign_identity','sibling_first','sibling_after','payment_undo_late','card_delete_late','wallet_currency_late','absent_foreign_ledger','absent_foreign_wallet']
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--case',choices=CASES);ap.add_argument('--negative-membership',action='store_true');ap.add_argument('--negative-ledger-identity',action='store_true');ap.add_argument('--negative-wallet-identity',action='store_true');args=ap.parse_args()
    assert not args.negative_membership or args.case=='sibling_after'
    assert not args.negative_ledger_identity or args.case=='absent_foreign_ledger'
    assert not args.negative_wallet_identity or args.case=='absent_foreign_wallet'
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
    def insert(row):return 'insert into public.due_occurrence_records select (jsonb_populate_record(null::public.due_occurrence_records,'+lit(row)+')).*;'
    assert sql(f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}');").splitlines()[-1]=='0'
    assert sql(f"select count(*) from pg_namespace where nspname='{SCHEMA}';").splitlines()[-1]=='0'
    assert sql(f"select count(*) from pg_stat_activity where application_name like '{PREFIX}%';").splitlines()[-1]=='0'
    setup=False;outcomes=[]
    try:
        fixture=(ROOT/'supabase/tests/database/card_paid_cycle_publication.sql').read_text().split("select pg_temp.capture('initial');",1)[0]
        fixture=fixture.replace('select no_plan();','').replace('71000000','72000000')
        raw=sql(fixture+"select pg_temp.capture('initial');select encode(convert_to(jsonb_build_object('cycle',pg_temp.cycle_payload(),'proof',(select to_jsonb(saved_proof) from proof saved_proof where name='initial'))::text,'UTF8'),'hex');commit;")
        setup=True;packet=json.loads(bytes.fromhex(next(l for l in raw.splitlines() if re.fullmatch(r'7b[0-9a-f]+',l))).decode())
        c=packet['cycle']
        if args.negative_membership:sql('alter table public.due_occurrence_records disable trigger due_occurrence_records_serialize_card_membership;')
        if args.negative_ledger_identity:sql('alter table public.ledger_transactions disable trigger ledger_transactions_serialize_card_payment_identity;')
        if args.negative_wallet_identity:sql('alter table public.ledger_wallets disable trigger ledger_wallets_serialize_card_payment_identity;')
        for index,case in enumerate([args.case] if args.case else CASES):
            proof=json.loads(sql("select jsonb_build_object('l',jsonb_build_object('72000000-0000-4000-8000-000000000301',(select to_jsonb(r) from public.ledger_transactions r where id='72000000-0000-4000-8000-000000000301')),'w',(select jsonb_object_agg(id::text,to_jsonb(r)) from public.ledger_wallets r where user_id='72000000-0000-4000-8000-000000000001'),'s','[]'::jsonb);").splitlines()[-1])
            desired=dict(c)
            if case in ('absent_foreign_ledger','absent_foreign_wallet'):
                desired.update(linked_transaction_id='72000000-0000-4000-8000-000000000398',deleted_at='2026-10-28T00:09:00Z')
                proof['l']={desired['linked_transaction_id']:None};proof['w']={}
                if case=='absent_foreign_wallet':desired['source_id']='72000000-0000-4000-8000-000000000298'
            rpc=auth(OWNER)+f"select public.mutate_card_paid_cycle({lit(desired)},0,false,{lit(proof['l'])},{lit(proof['w'])},{lit(proof['s'])});"
            release=168501+index*2;arrived=release+1;assert not lock_pid(release) and not lock_pid(arrived)
            gate=first=second=None;gate_pid=None
            try:
                pause_id='72000000-0000-4000-8000-000000000402' if case=='sibling_first' else EVENT
                device='72000000-0000-4000-8000-000000000902' if case=='sibling_first' else c['last_modified_by_device_id']
                sql(f"create schema {SCHEMA};create function {SCHEMA}.pause_marker() returns trigger language plpgsql as $$begin if new.id='{pause_id}' and new.user_id='{OWNER}' and new.last_modified_by_device_id='{device}' then perform pg_advisory_xact_lock({arrived});perform pg_advisory_xact_lock({release});end if;return new;end;$$;create trigger z_mistia_card_paid_race before insert on public.due_occurrence_records for each row execute function {SCHEMA}.pause_marker();")
                gate=launch(f'select pg_advisory_lock({release});select pg_sleep(11);','gate');gate_pid=barrier(release)
                sibling=dict(c,id='72000000-0000-4000-8000-000000000402',selected_month_key='2026-10',linked_transaction_id='72000000-0000-4000-8000-000000000302',last_modified_by_device_id='72000000-0000-4000-8000-000000000902')
                if case=='sibling_first':
                    first=launch(auth(OWNER)+insert(sibling),'first');barrier(arrived)
                    second=launch(rpc,'second');blocked=waiting('second',second)
                else:
                    first=launch(rpc,'first');barrier(arrived)
                    if case=='foreign_identity':
                        contender=dict(c,user_id=OTHER,source_id='72000000-0000-4000-8000-000000000299',linked_transaction_id='72000000-0000-4000-8000-000000000399',amount_minor_snapshot=75,last_modified_by_device_id='72000000-0000-4000-8000-000000000902')
                        sql(auth(OTHER)+insert(contender));blocked=True
                    else:
                        update={
                            'sibling_after':insert(sibling),
                            'payment_undo_late':"update public.ledger_transactions set deleted_at='2026-10-28T00:05:00Z',sync_version=sync_version+1 where id='72000000-0000-4000-8000-000000000301';",
                            'card_delete_late':"update public.ledger_wallets set deleted_at='2026-10-28T00:05:00Z',sync_version=sync_version+1 where id='72000000-0000-4000-8000-000000000201';",
                            'wallet_currency_late':"update public.ledger_wallets set currency_code='USD',sync_version=sync_version+1 where id='72000000-0000-4000-8000-000000000101';",
                            'absent_foreign_wallet':"insert into public.ledger_wallets select (jsonb_populate_record(null::public.ledger_wallets,to_jsonb(w)||jsonb_build_object('id','72000000-0000-4000-8000-000000000298'))).* from public.ledger_wallets w where id='72000000-0000-4000-8000-000000000102';",
                            'absent_foreign_ledger':"insert into public.ledger_transactions select (jsonb_populate_record(null::public.ledger_transactions,to_jsonb(t)||jsonb_build_object('id','72000000-0000-4000-8000-000000000398'))).* from public.ledger_transactions t where id='72000000-0000-4000-8000-000000000399';"
                        }[case]
                        second=launch(auth(OTHER if case in ('absent_foreign_ledger','absent_foreign_wallet') else OWNER)+update,'second');blocked=waiting('second',second)
                sql(f'select pg_terminate_backend({gate_pid});');gate_pid=None
                for p in [first,second]:
                    if p:p.wait(timeout=12)
                err1=first.stderr.read();err2=second.stderr.read() if second else ''
                if case=='foreign_identity':
                    actual=sql(f"select user_id,source_id,linked_transaction_id,amount_minor_snapshot,sync_version from public.due_occurrence_records where id='{EVENT}';").splitlines()[-1]
                    ok=first.returncode!=0 and 'card_payment_version_conflict' in err1 and actual==f'{OTHER}|72000000-0000-4000-8000-000000000299|72000000-0000-4000-8000-000000000399|75|1'
                elif case=='sibling_first':
                    ok=blocked and first.returncode==0 and second.returncode!=0 and 'card_payment_membership_changed' in err2 and sql(f"select count(*) from public.due_occurrence_records where id='{EVENT}';").splitlines()[-1]=='0'
                else:ok=blocked and first.returncode==second.returncode==0
                outcomes.append(ok);print(('PASS: ' if ok else 'FAIL: ')+case+'; contender serialized until compared commit='+str(blocked),flush=True)
                if not ok:print('Diagnostic exits '+str((first.returncode,second.returncode if second else None))+' errors '+err1[-300:]+err2[-300:],flush=True)
            finally:
                if gate_pid:sql(f'select pg_terminate_backend({gate_pid});')
                for p in [first,second,gate]:
                    if p:
                        try:p.wait(timeout=12)
                        except subprocess.TimeoutExpired:p.kill();p.wait()
                sql(f"drop trigger if exists z_mistia_card_paid_race on public.due_occurrence_records;drop schema if exists {SCHEMA} cascade;delete from public.due_occurrence_records where user_id in ('{OWNER}','{OTHER}') and id<>'72000000-0000-4000-8000-000000000499';update public.ledger_transactions set deleted_at=null where id='72000000-0000-4000-8000-000000000301';update public.ledger_wallets set deleted_at=null,currency_code='JPY' where id in ('72000000-0000-4000-8000-000000000101','72000000-0000-4000-8000-000000000201');delete from public.ledger_transactions where id='72000000-0000-4000-8000-000000000398' and user_id='{OTHER}';delete from public.ledger_wallets where id='72000000-0000-4000-8000-000000000298' and user_id='{OTHER}';")
        assert all(outcomes),'Actual card paid-cycle concurrency invariant failed'
    finally:
        if setup:
            sql(f"alter table public.ledger_wallets enable trigger ledger_wallets_serialize_card_payment_identity;alter table public.ledger_transactions enable trigger ledger_transactions_serialize_card_payment_identity;alter table public.due_occurrence_records enable trigger due_occurrence_records_serialize_card_membership;drop trigger if exists z_mistia_card_paid_race on public.due_occurrence_records;drop schema if exists {SCHEMA} cascade;delete from auth.users where id in ('{OWNER}','{OTHER}');")
            assert sql(f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}');").splitlines()[-1]=='0'
        ports()
if __name__=='__main__':main()
