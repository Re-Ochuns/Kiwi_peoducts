"""Explicitly isolated, synthetic local API acceptance for Issue #62.
Requires kiwi_issue62 at port 56421. Seeds only that dedicated project's DB.
Rebuild that dedicated DB after running; never run against another environment.
"""
import base64
import concurrent.futures
import hashlib
import hmac
import json
from pathlib import Path
import subprocess
import time
import urllib.request
import urllib.error
import uuid

ROOT = Path(__file__).resolve().parents[1]
WORKDIR = ROOT.parent / "issue62-db"
DB = "supabase_db_kiwi_issue62"
assert 'project_id = "kiwi_issue62"' in (WORKDIR / "supabase/config.toml").read_text()
assert "port = 56421" in (WORKDIR / "supabase/config.toml").read_text()
CLI = ROOT / "node_modules/.bin/supabase"
settings = json.loads(subprocess.check_output(
    [str(CLI), "status", "--workdir", str(WORKDIR), "-o", "json"],
    stderr=subprocess.DEVNULL))
url = settings["API_URL"]
assert url in ("http://127.0.0.1:56421", "http://localhost:56421"), "Unexpected API target"
secret = settings["JWT_SECRET"]
anon = settings["ANON_KEY"]
member = "41000000-0000-0000-0000-000000000002"
lot = "49000000-0000-0000-0000-000000000001"

def sql(text):
    return subprocess.check_output(
        ["docker", "exec", "-i", DB, "psql", "-U", "postgres", "-d", "postgres",
         "-At", "-v", "ON_ERROR_STOP=1"], input=text.encode()).decode()

assert sql(f"select count(*) from public.ripening_lots where id='{lot}';").strip() == "0",     "Synthetic fixture already exists; rebuild only issue62-db before retrying"
fixture = (ROOT / "supabase/tests/00170_ripening_work_rpc_test.sql").read_text()
fixture = fixture[:fixture.index("create function pg_temp.work_req")]
fixture = fixture.replace("select no_plan();",
    "set local search_path=public,extensions; create extension if not exists pgtap with schema extensions; select no_plan();")
sql(fixture + "\ncommit;")

def token(sub):
    def enc(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).rstrip(b"=")
    data = enc({"alg": "HS256", "typ": "JWT"}) + b"." + enc(
        {"role": "authenticated", "sub": sub, "aud": "authenticated", "exp": int(time.time())+600})
    return (data + b"." + base64.urlsafe_b64encode(
        hmac.new(secret.encode(), data, hashlib.sha256).digest()).rstrip(b"=")).decode()

def request(path, body=None, sub=member):
    headers = {"apikey": anon, "Authorization": "Bearer " + token(sub)}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url + "/rest/v1/" + path,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

def details():
    return request("rpc/ripening_work_get", {"ripening_lot_id_value": lot})

def payload(extra=None, operation=None):
    value = {"ripening_lot_id": lot, "expected_version": details()["version"],
             "actual_temperature": 20, "checked": True,
             "location_id": "44000000-0000-0000-0000-000000000001",
             "performed_by": "43000000-0000-0000-0000-000000000001"}
    value.update(extra or {})
    return {"meta": {"idempotency_key": operation or str(uuid.uuid4()),
                     "correlation_id": str(uuid.uuid4())}, "input": value}

def call(kind, req, sub=member):
    return request("rpc/ripening_" + kind + "_complete", {"req": req}, sub)

initial = details()
assert call("ethylene_injection", payload(), "41000000-0000-0000-0000-000000000001")["error"]["code"] == "AUTH_FORBIDDEN"
assert call("ethylene_injection", payload({"checked": False}))["error"]["code"] == "CONFIRMATION_REQUIRED"
req = payload()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda _: call("ethylene_injection", req), range(2)))
assert all(r["ok"] for r in results)
assert sum(r.get("idempotent_replay", False) for r in results) == 1
changed = json.loads(json.dumps(req))
changed["input"]["actual_temperature"] = 21
assert call("ethylene_injection", changed)["error"]["code"] == "IDEMPOTENCY_KEY_REUSED"
assert sql("select current_weight_kg from public.containers where id='48500000-0000-0000-0000-000000000001';").strip() in ("2", "2.00")
assert sql("select count(*) from public.inventory_events;").strip() == "2"
assert call("ripeness", payload())["error"]["code"] == "INVALID_WORK_STATE"

removal = payload({"rest_temperature": 18})
other = json.loads(json.dumps(removal))
other["meta"]["idempotency_key"] = str(uuid.uuid4())
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda r: call("ethylene_removal", r), [removal, other]))
assert sum(r["ok"] for r in results) == 1
assert [r["error"]["code"] for r in results if not r["ok"]] == ["CONFLICT_STALE"]
assert call("ripeness", payload())["ok"]
final = details()
assert final["status"] == "completed"
assert final["containers"][0]["status"] == "shippable"
assert final["planned_ethylene_at"] == initial["planned_ethylene_at"]
assert final["planned_completion_at"] == initial["planned_completion_at"]
assert final["allocations"] == initial["allocations"]
assert len(final["results"]) == 3 and all(t["status"] == "completed" for t in final["tasks"])
assert call("ethylene_injection", payload())["error"]["code"] == "INVALID_WORK_STATE"
print(json.dumps({"result": "PASS", "api": url,
    "verified": ["auth denial", "required confirmation", "3 stages",
                 "same-key concurrent replay", "different-key concurrent conflict",
                 "partial source balance", "allocations and plans unchanged",
                 "task completion", "reprocessing denied"]}))
