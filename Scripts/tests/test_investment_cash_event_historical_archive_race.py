#!/usr/bin/env python3
"""Verify a historical cash event retains its holder against a concurrent archive.

The current default points elsewhere; a confirmed deposit still uses its captured
wallet. Its atomic RPC must hold the archive until the positive allocation commits,
then reject retirement. Only this project's guarded loopback local Docker DB and
an isolated synthetic owner are used; no production connection or credentials.
"""
import json
import pathlib
import re
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
OWNER = '63000000-0000-4000-8000-000000000001'
DESTINATION = '63000000-0000-4000-8000-000000000101'
EVENT = '63000000-0000-4000-8000-000000000501'
RELEASE, ARRIVED = 163101, 163102


def main():
    docker = shutil.which('docker') or '/usr/local/bin/docker'
    project = re.search(r'^project_id\s*=\s*"([a-z0-9_-]+)"', (ROOT / 'supabase/config.toml').read_text(), re.M).group(1)
    endpoint = subprocess.check_output([docker, 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], text=True).strip()
    assert endpoint.startswith('unix://'), 'Only the local Docker socket is supported'
    container = 'supabase_db_' + project
    state = json.loads(subprocess.check_output([docker, 'inspect', container], text=True))[0]
    for group in (state['HostConfig'].get('PortBindings'), state['NetworkSettings'].get('Ports')):
        assert group and all(p['HostIp'] == '127.0.0.1' for values in group.values() for p in (values or []))
    assert state['State']['Running']
    command = [docker, 'exec', '-i', container, 'psql', '-X', '-A', '-t', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']

    def sql(text):
        p = subprocess.run(command, input=text, capture_output=True, text=True, timeout=15)
        assert p.returncode == 0, p.stderr.strip()
        return p.stdout.strip()

    def launch(text):
        p = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        p.stdin.write(text)
        p.stdin.close()
        return p

    def lock_pid(key):
        value = sql(f"select pid from pg_locks where locktype='advisory' and classid=0 and objid={key} and objsubid=1 and granted;")
        return int(value) if value else None

    def wait_for(condition):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.1)
        raise AssertionError('Historical cash archive race did not reach its barrier')

    assert sql(f"select count(*) from auth.users where id='{OWNER}';") == '0', 'Fixture already exists; nothing changed'
    assert not lock_pid(RELEASE) and not lock_pid(ARRIVED)
    setup = False
    gate = move = archive = None
    gate_pid = None
    try:
        # Reuse only the synthetic fixture creation; all pgTAP assertions remain in
        # their own rollback test. pg_temp helper functions disappear with psql.
        fixture = (ROOT / 'supabase/tests/database/investment_cash_event_historical_routing.sql').read_text()
        fixture = fixture.split('-- The default changes', 1)[0].replace('57000000', '63000000')
        fixture = fixture.replace('select no_plan();', '')
        changed_default = f"update public.ledger_wallets set investment_linked_wallet_id='63000000-0000-4000-8000-000000000102' where id=public.investment_system_wallet_id('{OWNER}');"
        raw = sql(fixture + changed_default + f"select encode(convert_to(pg_temp.cash_proposal('{EVENT}')::text,'UTF8'),'hex');commit;")
        setup = True
        encoded = next(line for line in raw.splitlines() if re.fullmatch(r'7b[0-9a-f]+', line))
        transaction = json.loads(bytes.fromhex(encoded).decode())
        positive = sql(f"select public.investment_ledger_id('{EVENT}','cash-transfer-posting');")
        sql(f"""
create function public.mistia_historical_cash_archive_race_barrier() returns trigger language plpgsql as $$
begin
 if new.id='{positive}'::uuid then
  perform pg_advisory_xact_lock({ARRIVED});
  perform pg_advisory_xact_lock({RELEASE});
 end if;
 return new;
end;
$$;
create trigger mistia_historical_cash_archive_race_barrier before insert on public.investment_wallet_postings
for each row execute function public.mistia_historical_cash_archive_race_barrier();
""")
        gate = launch(f'select pg_advisory_lock({RELEASE});select pg_sleep(30);')
        wait_for(lambda: lock_pid(RELEASE))
        gate_pid = lock_pid(RELEASE)
        auth = f"select set_config('request.jwt.claim.sub','{OWNER}',false);select set_config('request.jwt.claim.role','authenticated',false);"
        move = launch(auth + f"select id from public.mutate_investment_cash_event('{json.dumps(transaction)}'::jsonb,'[]',0,'{{}}',false);")
        wait_for(lambda: lock_pid(ARRIVED))
        label = 'mistia_historical_cash_archive_contender'
        archive = launch(f"set application_name='{label}';" + auth + f"update public.ledger_wallets set is_archived=true where id='{DESTINATION}';")
        wait_for(lambda: archive.poll() is not None or sql(f"select count(*) from pg_stat_activity where application_name='{label}' and wait_event_type='Lock';") == '1')
        # Release in both modes, preserving the observed pre-release completion.
        overtook = archive.poll() is not None
        assert sql(f'select pg_terminate_backend({gate_pid});') == 't'
        gate_pid = None
        move.wait(timeout=10)
        archive.wait(timeout=10)
        assert move.returncode == 0, move.stderr.read()
        error = archive.stderr.read()
        actual = sql(f"select is_archived::text||':'||(select sum(accounting_amount_minor)::text from public.investment_wallet_postings where wallet_id='{DESTINATION}' and deleted_at is null) from public.ledger_wallets where id='{DESTINATION}';")
        assert not overtook and archive.returncode != 0 and 'investment cash held' in error and actual == 'false:50', f'Archive overtook historical cash event (early={overtook}, archiveExit={archive.returncode}, wallet={actual})'
        assert sql(f"select destination_wallet_id::text from public.ledger_transactions where id='{EVENT}';") == DESTINATION
        assert sql(f"select investment_linked_wallet_id::text from public.ledger_wallets where id=public.investment_system_wallet_id('{OWNER}');") == '63000000-0000-4000-8000-000000000102'
        print('PASS: historical cash event locked its captured holder until commit; concurrent archive rejected, active holder has50, later default unchanged')
    finally:
        if gate_pid:
            sql(f'select pg_terminate_backend({gate_pid});')
        for process in (move, archive, gate):
            if process:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        if setup:
            # The dedicated system-wallet DELETE trigger also protects fixtures.
            # Disable only that trigger inside this atomic local cleanup, delete
            # only our synthetic owner, and restore it before committing.
            sql(f"begin;drop trigger if exists mistia_historical_cash_archive_race_barrier on public.investment_wallet_postings;drop function if exists public.mistia_historical_cash_archive_race_barrier();delete from public.investment_wallet_postings where user_id='{OWNER}';delete from public.investment_trades where user_id='{OWNER}';delete from public.investment_assets where user_id='{OWNER}';delete from public.investment_channels where user_id='{OWNER}';delete from public.ledger_transactions where user_id='{OWNER}';alter table public.ledger_wallets disable trigger ledger_wallets_enforce_investment_system_wallet;delete from public.ledger_wallets where user_id='{OWNER}';alter table public.ledger_wallets enable trigger ledger_wallets_enforce_investment_system_wallet;delete from auth.users where id='{OWNER}';commit;")
            assert sql(f"select count(*) from auth.users where id='{OWNER}';") == '0'
        assert not lock_pid(RELEASE) and not lock_pid(ARRIVED)


if __name__ == '__main__':
    main()
