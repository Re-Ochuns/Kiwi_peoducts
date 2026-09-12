"""Prepare synthetic Auth users for the S2 live Repository acceptance tests.
Requires the dedicated kiwi_s2_acceptance instance, never a shared database.
Usage: SUPABASE_CMD=/path/to/supabase python3 scripts/prepare_stage2_live.py RUNTIME
"""
import json, os, subprocess, urllib.request, urllib.error, uuid, sys
from pathlib import Path
from decimal import Decimal

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = sys.argv[1]
DB = "supabase_db_kiwi_s2_acceptance"
BASE = "http://127.0.0.1:58321"
cli = os.environ.get("SUPABASE_CMD", "supabase")
runtime = Path(RUNTIME).resolve()
import tomllib
settings = tomllib.loads((runtime / "supabase/config.toml").read_text())
assert settings["project_id"] == "kiwi_s2_acceptance", "Refusing non-S2 project"
assert settings["api"]["port"] == 58321 and settings["db"]["port"] == 58322
cfg = json.loads(subprocess.check_output([cli, "status", "--workdir", str(runtime), "-o", "json"], text=True, stderr=subprocess.DEVNULL))
assert cfg["API_URL"] == BASE, "Refusing non-verification endpoint"
key = cfg["ANON_KEY"]
def sql(query):
    return subprocess.check_output(["docker","exec","-i",DB,"psql","-X","-U","postgres","-d","postgres","-At","-v","ON_ERROR_STOP=1"],input=query,text=True).strip()
def http(path, body, token=None):
    req=urllib.request.Request(BASE+path,data=json.dumps(body).encode(),headers={
        "apikey":key,"Authorization":"Bearer "+(token or key),"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(req,timeout=30) as r: return r.status,json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code,json.loads(e.read())
def user(role):
    email="s2-acceptance-"+str(uuid.uuid4())+"@example.com"
    password=str(uuid.uuid4())+"Aa1!"
    uid=str(uuid.uuid4())
    # Synthetic Google-profile fixture with a test-only password; not an OAuth test.
    sql("""insert into auth.users(instance_id,id,aud,role,email,encrypted_password,
        email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
        confirmation_token,recovery_token,email_change_token_new,email_change)
        values('00000000-0000-0000-0000-000000000000','%s','authenticated',
        'authenticated','%s',extensions.crypt('%s',extensions.gen_salt('bf')),now(),
        '{"provider":"google","providers":["google"]}','{}',now(),now(),'','','','');"""
        % (uid,email,password))
    if role:
        sql("select private.set_user_access('"+uid+"','active',array['"+role+"']);")
    status,data=http("/auth/v1/token?grant_type=password",{"email":email,"password":password})
    assert status==200,(status,data)
    return uid,data["access_token"]


config={"url":BASE,"key":key}
for role in ["administrator","member",None]:
 uid,token=user(role)
 config[role or "pending"]={"id":uid,"token":token}
config["variety"]=sql("select id from public.varieties where is_active order by id limit 1")
config["grade"]=sql("select id from public.grades where code='M'")
path=Path(RUNTIME)/"credentials.json"
with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as output:
    json.dump(config, output)
path.chmod(0o600)
print("Prepared synthetic Auth users; credentials saved privately")

source=(ROOT/'supabase/tests/00110_ripening_plan_rpc_test.sql').read_text()
fixture=source[source.index('insert into public.sorting_results'):source.index('create function pg_temp.req')]
if sql("select count(*) from public.containers where id='53500000-0000-0000-0000-000000000001'") == "0":
    sql(fixture)
else:
    assert Decimal(sql("select reserved_weight_kg from public.containers where id='53500000-0000-0000-0000-000000000001'")) == 0, "Fixture is in use"
print('Prepared isolated 10kg stock fixture')
