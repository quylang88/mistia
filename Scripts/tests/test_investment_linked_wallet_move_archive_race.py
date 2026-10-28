#!/usr/bin/env python3
"""Verify a concurrent wallet archive cannot overtake a confirmed cash move.

--legacy-baseline characterizes the two-argument API without wallet share locks:
archive commits while the positive posting is paused before insertion. The default
compared API must hold the archive until retained cash is visible, then reject it.
Only this project's loopback Docker DB and a rolled-back/cleaned synthetic owner.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
OWNER = '61000000-0000-4000-8000-000000000001'
DESTINATION = '61000000-0000-4000-8000-000000000102'
EVENT = '61000000-0000-4000-8000-000000000501'
RELEASE, ARRIVED = 161101, 161102


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--legacy-baseline', action='store_true')
    args = parser.parse_args()
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
        raise AssertionError('Linked move archive race did not reach its barrier')

    assert sql(f"select count(*) from auth.users where id='{OWNER}';") == '0', 'Fixture already exists; nothing changed'
    assert not lock_pid(RELEASE) and not lock_pid(ARRIVED)
    setup = False
    gate = move = archive = None
    gate_pid = None
    try:
        # Reuse only the synthetic fixture creation; all pgTAP assertions remain in
        # their own rollback test. pg_temp helper functions disappear with psql.
        fixture = (ROOT / 'supabase/tests/database/investment_linked_wallet_move_publication.sql').read_text()
        fixture = fixture.split("select lives_ok('select pg_temp.publish()'", 1)[0]
        fixture = fixture.replace('select no_plan();', '')
        raw = sql(fixture + "select encode(convert_to(pg_temp.rows()::text,'UTF8'),'hex');commit;")
        setup = True
        encoded = next(line for line in raw.splitlines() if re.fullmatch(r'7b[0-9a-f]+|5b[0-9a-f]+', line))
        rows = json.loads(bytes.fromhex(encoded).decode())
        positive = next(row['id'] for row in rows if row['amount_minor'] > 0)
        sql(f"""
create function public.mistia_linked_move_archive_race_barrier() returns trigger language plpgsql as $$
begin
 if new.id='{positive}'::uuid then
  perform pg_advisory_xact_lock({ARRIVED});
  perform pg_advisory_xact_lock({RELEASE});
 end if;
 return new;
end;
$$;
create trigger mistia_linked_move_archive_race_barrier before insert on public.investment_wallet_postings
for each row execute function public.mistia_linked_move_archive_race_barrier();
""")
        gate = launch(f'select pg_advisory_lock({RELEASE});select pg_sleep(30);')
        wait_for(lambda: lock_pid(RELEASE))
        gate_pid = lock_pid(RELEASE)
        auth = f"select set_config('request.jwt.claim.sub','{OWNER}',false);select set_config('request.jwt.claim.role','authenticated',false);"
        versions = json.dumps({row['id']: 0 for row in rows})
        values = f"'{json.dumps(rows)}'::jsonb," + ('false' if args.legacy_baseline else f"'{versions}'::jsonb,false")
        move = launch(auth + f'select id from public.mutate_investment_cash_postings({values});')
        wait_for(lambda: lock_pid(ARRIVED))
        label = 'mistia_linked_move_archive_contender'
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
        assert not overtook and archive.returncode != 0 and 'investment cash held' in error and actual == 'false:50', f'Archive overtook confirmed cash move (early={overtook}, archiveExit={archive.returncode}, wallet={actual})'
        print('PASS: concurrent archive waited for compared cash move, then rejected retained cash; active wallet holds exactly50')
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
            sql(f"begin;drop trigger if exists mistia_linked_move_archive_race_barrier on public.investment_wallet_postings;drop function if exists public.mistia_linked_move_archive_race_barrier();delete from public.investment_wallet_postings where user_id='{OWNER}';delete from public.ledger_transactions where user_id='{OWNER}';alter table public.ledger_wallets disable trigger ledger_wallets_enforce_investment_system_wallet;delete from public.ledger_wallets where user_id='{OWNER}';alter table public.ledger_wallets enable trigger ledger_wallets_enforce_investment_system_wallet;delete from auth.users where id='{OWNER}';commit;")
            assert sql(f"select count(*) from auth.users where id='{OWNER}';") == '0'
        assert not lock_pid(RELEASE) and not lock_pid(ARRIVED)


if __name__ == '__main__':
    main()
