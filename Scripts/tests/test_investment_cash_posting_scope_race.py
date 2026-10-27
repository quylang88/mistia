#!/usr/bin/env python3
"""Exercise a real two-caller cash RPC race against this project's local Docker DB.

Requires only Python's standard library and Docker. Synthetic fixtures and the
barrier trigger are removed in finally; no database URL or credentials are used.
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
OWNER_A = "58000000-0000-4000-8000-000000000001"
OWNER_B = "58000000-0000-4000-8000-000000000002"
WALLET_A = "58000000-0000-4000-8000-000000000101"
WALLET_B = "58000000-0000-4000-8000-000000000102"
LEDGER_A = "58000000-0000-4000-8000-000000000201"
LEDGER_B = "58000000-0000-4000-8000-000000000202"
POSTING = "58000000-0000-4000-8000-000000000301"
SCHEMA = "mistia_cash_posting_scope_race_test"
RELEASE_LOCK = 157001
ARRIVED_LOCK = 157002


def main():
    project = re.search(r'^project_id\s*=\s*"([a-z0-9_-]+)"', (ROOT / "supabase/config.toml").read_text(), re.M).group(1)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", default="supabase_db_" + project)
    args = parser.parse_args()
    assert args.container == "supabase_db_" + project, "Only this project's local database is supported"
    endpoint = subprocess.check_output([DOCKER, "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], text=True).strip()
    assert endpoint.startswith("unix://"), "A local Docker socket is required"
    state = json.loads(subprocess.check_output([DOCKER, "inspect", args.container], text=True))[0]
    assert state["State"]["Running"]
    ports = [binding for bindings in state["NetworkSettings"]["Ports"].values() for binding in (bindings or [])]
    assert ports and all(p["HostIp"] == "127.0.0.1" for p in ports), "Explicit loopback binding is required"

    command = [DOCKER, "exec", "-i", args.container, "psql", "-X", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]

    def sql(text):
        result = subprocess.run(command, input=text, capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise AssertionError("Local fixture SQL failed: " + result.stderr.strip())
        return result.stdout.strip()

    def lock_pid(key):
        value = sql(f"select pid from pg_locks where locktype='advisory' and classid=0 and objid={key} and objsubid=1 and granted;")
        return int(value) if value else None

    def wait_for_lock(key):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            pid = lock_pid(key)
            if pid:
                return pid
            time.sleep(0.1)
        raise AssertionError("Local race barrier was not reached")

    def proposal(owner, wallet, ledger, amount):
        return json.dumps({
            "id": POSTING, "user_id": owner, "event_id": ledger,
            "wallet_id": wallet, "ledger_transaction_id": ledger,
            "role_raw_value": "cashCorrection", "cash_bucket_raw_value": "booked", "cash_origin_raw_value": "manual",
            "amount_minor": amount, "accounting_amount_minor": amount,
            "currency_code": "VND", "accounting_currency_code": "VND",
            "created_at": "2026-10-27T00:00:00Z", "updated_at": "2026-10-27T00:00:00Z", "occurred_at": "2026-10-27T00:00:00Z",
            "deleted_at": None, "last_modified_by_device_id": "58000000-0000-4000-8000-000000000901",
        })

    def rpc(owner, wallet, ledger, amount):
        return (f"select set_config('request.jwt.claim.sub','{owner}',false);"
                "select set_config('request.jwt.claim.role','authenticated',false);"
                f"select (public.mutate_investment_cash_posting('{proposal(owner, wallet, ledger, amount)}'::jsonb,0,false)).id;")

    assert sql(f"select count(*) from auth.users where id in ('{OWNER_A}','{OWNER_B}');") == "0", "Fixture IDs already exist; nothing was changed"
    assert sql(f"select count(*) from pg_namespace where nspname='{SCHEMA}';") == "0"
    assert not lock_pid(RELEASE_LOCK) and not lock_pid(ARRIVED_LOCK)
    assert sql("select count(*) from pg_trigger where tgname='mistia_cash_posting_scope_race' and tgrelid='public.investment_wallet_postings'::regclass;") == "0"
    gate = contender = None
    gate_pid = None
    setup_complete = False
    try:
        sql(f"""
begin;
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('{OWNER_A}','authenticated','authenticated','cash-race-a@mistia.test','',now(),'{{"provider":"email","providers":["email"]}}','{{}}',now(),now()),
('{OWNER_B}','authenticated','authenticated','cash-race-b@mistia.test','',now(),'{{"provider":"email","providers":["email"]}}','{{}}',now(),now());
insert into public.user_profiles(user_id,display_name) values ('{OWNER_A}','Cash race fixture'),('{OWNER_B}','Cash race fixture') on conflict(user_id) do nothing;
insert into public.ledger_wallets(id,user_id,name,kind_raw_value,icon_symbol_name,icon_color_hex,currency_code,opening_balance_minor)
values ('{WALLET_A}','{OWNER_A}','A cash','cash','banknote.fill','#111111','VND',10000),('{WALLET_B}','{OWNER_B}','B cash','cash','banknote.fill','#111111','VND',10000);
insert into public.ledger_transactions(id,user_id,primary_kind_raw_value,entry_status_raw_value,title,amount_minor,occurred_at,source_wallet_id,source_currency_code,reporting_currency_code,reporting_amount_minor,created_by_user_id,last_modified_by_user_id)
values ('{LEDGER_A}','{OWNER_A}','expense','posted','A race fixture',100,'2026-10-27T00:00:00Z','{WALLET_A}','VND','VND',100,'{OWNER_A}','{OWNER_A}'),
('{LEDGER_B}','{OWNER_B}','expense','posted','B race fixture',100,'2026-10-27T00:00:00Z','{WALLET_B}','VND','VND',100,'{OWNER_B}','{OWNER_B}');
create schema {SCHEMA};
create function {SCHEMA}.wait_after_absence() returns trigger language plpgsql as $$
begin
    if new.id='{POSTING}' and new.user_id='{OWNER_A}' then
        perform pg_advisory_xact_lock({ARRIVED_LOCK});
        perform pg_advisory_xact_lock({RELEASE_LOCK});
    end if;
    return new;
end;
$$;
create trigger mistia_cash_posting_scope_race before insert on public.investment_wallet_postings for each row execute function {SCHEMA}.wait_after_absence();
commit;
""")
        setup_complete = True
        gate = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        gate.stdin.write(f"select pg_advisory_lock({RELEASE_LOCK});select pg_sleep(30);\n")
        gate.stdin.close()
        gate_pid = wait_for_lock(RELEASE_LOCK)
        contender = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        contender.stdin.write(rpc(OWNER_A, WALLET_A, LEDGER_A, 99))
        contender.stdin.close()
        wait_for_lock(ARRIVED_LOCK)  # The initial absent-row SELECT completed; insertion is blocked.
        foreign = sql(rpc(OWNER_B, WALLET_B, LEDGER_B, 50))
        assert foreign.splitlines()[-1] == POSTING
        assert sql(f"select pg_terminate_backend({gate_pid});") == "t"
        gate_pid = None
        contender.wait(timeout=10)
        error = contender.stderr.read()
        expected = f"{OWNER_B}|{WALLET_B}|{LEDGER_B}|50|1|t"
        actual = sql(f"select user_id,wallet_id,ledger_transaction_id,accounting_amount_minor,sync_version,deleted_at is null from public.investment_wallet_postings where id='{POSTING}';")
        assert contender.returncode != 0 and "Invalid investment cash posting" in error, f"An absent-row contender redirected the foreign committed posting (exit={contender.returncode}, row={actual})"
        assert actual == expected, "Foreign identity, business, version or active state changed"
        print("PASS: real two-caller absent-row race rejected; foreign committed posting remains intact")
    finally:
        if gate_pid:
            sql(f"select pg_terminate_backend({gate_pid});")
        for process in (contender, gate):
            if process:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        if setup_complete:
            sql(f"""
    begin;
    drop trigger if exists mistia_cash_posting_scope_race on public.investment_wallet_postings;
    drop schema if exists {SCHEMA} cascade;
    delete from public.investment_wallet_postings where user_id in ('{OWNER_A}','{OWNER_B}');
    delete from public.ledger_transactions where user_id in ('{OWNER_A}','{OWNER_B}');
    delete from public.ledger_wallets where user_id in ('{OWNER_A}','{OWNER_B}');
    delete from auth.users where id in ('{OWNER_A}','{OWNER_B}');
    commit;
    """)
            assert sql(f"select count(*) from auth.users where id in ('{OWNER_A}','{OWNER_B}');") == "0"
            assert not lock_pid(RELEASE_LOCK) and not lock_pid(ARRIVED_LOCK)

if __name__ == "__main__":
    main()
