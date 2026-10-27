#!/usr/bin/env python3
"""Check stale-update and absent-create cash batch races on this project's local DB.

--legacy-baseline intentionally reproduces the old two-argument API losing the
committed winner. It must fail; the default compared API must reject both races.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCKER = shutil.which("docker") or "/usr/local/bin/docker"
OWNER = "60000000-0000-4000-8000-000000000001"
WALLET = "60000000-0000-4000-8000-000000000101"
LEDGER = "60000000-0000-4000-8000-000000000201"
FIRST = "60000000-0000-4000-8000-000000000301"
SECOND = "60000000-0000-4000-8000-000000000303"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy-baseline", action="store_true")
    args = parser.parse_args()
    project = re.search(r'^project_id\s*=\s*"([a-z0-9_-]+)"', (ROOT / "supabase/config.toml").read_text(), re.M).group(1)
    endpoint = subprocess.check_output([DOCKER, "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], text=True).strip()
    assert endpoint.startswith("unix://"), "Only a local Docker socket is supported"
    container = "supabase_db_" + project
    state = json.loads(subprocess.check_output([DOCKER, "inspect", container], text=True))[0]
    bindings = [p for ports in state["NetworkSettings"]["Ports"].values() for p in (ports or [])]
    assert state["State"]["Running"] and bindings and all(p["HostIp"] == "127.0.0.1" for p in bindings)
    command = [DOCKER, "exec", "-i", container, "psql", "-X", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]

    def sql(text):
        result = subprocess.run(command, input=text, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, "Local fixture SQL failed: " + result.stderr.strip()
        return result.stdout.strip()

    def lock_pid(key):
        value = sql(f"select pid from pg_locks where locktype='advisory' and classid=0 and objid={key} and objsubid=1 and granted;")
        return int(value) if value else None

    def wait_for(condition):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.1)
        raise AssertionError("Cash comparison race did not reach its barrier")

    def launch(text):
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        process.stdin.write(text)
        process.stdin.close()
        return process

    auth = f"select set_config('request.jwt.claim.sub','{OWNER}',false);select set_config('request.jwt.claim.role','authenticated',false);"

    def row(identity, amount):
        return json.dumps({"id": identity, "user_id": OWNER, "event_id": LEDGER, "wallet_id": WALLET,
            "ledger_transaction_id": LEDGER, "role_raw_value": "cashCorrection", "cash_bucket_raw_value": "booked", "cash_origin_raw_value": "manual",
            "amount_minor": amount, "accounting_amount_minor": amount, "currency_code": "VND", "accounting_currency_code": "VND",
            "occurred_at": "2026-10-27T00:00:00Z", "created_at": "2026-10-27T00:00:00Z", "updated_at": "2026-10-27T00:00:00Z",
            "deleted_at": None, "last_modified_by_device_id": "60000000-0000-4000-8000-000000000901"})

    def batch(first_amount, second_amount, first_version, second_version, legacy=False):
        rows = f"jsonb_build_array('{row(FIRST, first_amount)}'::jsonb,'{row(SECOND, second_amount)}'::jsonb)"
        versions = f"jsonb_build_object('{FIRST}',{first_version},'{SECOND}',{second_version})"
        values = f"{rows},false" if legacy else f"{rows},{versions},false"
        return f"select id from public.mutate_investment_cash_postings({values});"

    assert sql(f"select count(*) from auth.users where id='{OWNER}';") == "0", "Fixture owner exists; nothing was changed"
    setup_complete = False
    try:
        sql(f"""
begin;
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('{OWNER}','authenticated','authenticated','cash-comparison-race@mistia.test','',now(),'{{"provider":"email","providers":["email"]}}','{{}}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('{OWNER}','Cash comparison fixture') on conflict(user_id) do nothing;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('{WALLET}','{OWNER}','Cash','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values ('{LEDGER}','{OWNER}','expense','posted','Comparison race fixture',100,'2026-10-27T00:00:00Z','{WALLET}','VND','VND',100,'{OWNER}','{OWNER}');
commit;
""")
        setup_complete = True
        sql(auth + batch(20, 30, 0, 0))
        for index, second_base in enumerate((1, 0)):
            if second_base == 0:
                sql(f"delete from public.investment_wallet_postings where id='{SECOND}' and user_id='{OWNER}';")
            release = 158001 + index * 2
            arrived = release + 1
            assert not lock_pid(release) and not lock_pid(arrived)
            gate = winner = contender = None
            gate_pid = None
            label = f"mistia_compared_cash_batch_contender_{index}"
            try:
                gate = launch(f"select pg_advisory_lock({release});select pg_sleep(30);")
                wait_for(lambda: lock_pid(release))
                gate_pid = lock_pid(release)
                winner = launch("begin;" + auth + f"select (public.mutate_investment_cash_posting('{row(SECOND, 50)}'::jsonb,{second_base},false)).id;select pg_advisory_xact_lock({arrived});select pg_advisory_xact_lock({release});commit;")
                wait_for(lambda: lock_pid(arrived))
                contender = launch(f"set application_name='{label}';" + auth + batch(99, 40, 1, second_base, args.legacy_baseline))
                wait_for(lambda: sql(f"select count(*) from pg_stat_activity where application_name='{label}' and wait_event='advisory';") == "1")
                assert sql(f"select pg_terminate_backend({gate_pid});") == "t"
                gate_pid = None
                winner.wait(timeout=10)
                assert winner.returncode == 0, winner.stderr.read()
                contender.wait(timeout=10)
                error = contender.stderr.read()
                actual = sql(f"select string_agg(id::text||':'||accounting_amount_minor::text||':'||sync_version::text,',' order by id) from public.investment_wallet_postings where user_id='{OWNER}';")
                assert contender.returncode != 0 and "version_conflict" in error, f"Batch lost the committed winner (exit={contender.returncode}, rows={actual})"
                assert actual == f"{FIRST}:20:1,{SECOND}:50:{second_base + 1}", "Stale batch partially changed financial rows"
                print(f"PASS: compared batch rejected {'stale update' if second_base else 'absent create'} race; winner and unrelated row preserved")
            finally:
                if gate_pid:
                    sql(f"select pg_terminate_backend({gate_pid});")
                for process in (winner, contender, gate):
                    if process:
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                assert not lock_pid(release) and not lock_pid(arrived)
    finally:
        if setup_complete:
            sql(f"begin;delete from public.investment_wallet_postings where user_id='{OWNER}';delete from public.ledger_transactions where user_id='{OWNER}';delete from public.ledger_wallets where user_id='{OWNER}';delete from auth.users where id='{OWNER}';commit;")
            assert sql(f"select count(*) from auth.users where id='{OWNER}';") == "0"


if __name__ == "__main__":
    main()
