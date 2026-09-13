"""Verify shipment RPCs through local Auth and PostgREST.
Requires a freshly reset dedicated kiwi_issue64 instance, never a shared database.
Usage: SUPABASE_CMD=/path/to/supabase python3 scripts/verify_shipment_http.py RUNTIME
"""
import json, os, subprocess, urllib.request, urllib.error, uuid, sys
from pathlib import Path
from decimal import Decimal

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = sys.argv[1]
DB = "supabase_db_kiwi_issue64"
BASE = "http://127.0.0.1:59321"
cli = os.environ.get("SUPABASE_CMD", "supabase")
runtime = Path(RUNTIME).resolve()
import tomllib
settings = tomllib.loads((runtime / "supabase/config.toml").read_text())
assert settings["project_id"] == "kiwi_issue64", "Refusing non-shipment verification project"
assert settings["api"]["port"] == 59321 and settings["db"]["port"] == 59322
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
    email="shipment-acceptance-"+str(uuid.uuid4())+"@example.com"
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



from concurrent.futures import ThreadPoolExecutor
fixture=(ROOT/'supabase/tests/00170_shipment_rpc_test.sql').read_text()
sql('begin;'+fixture[fixture.index('insert into auth.users'):fixture.index('create function pg_temp.req')]+'commit;')
uid,token=user('member')
pending,pending_token=user(None)
order='53300000-0000-0000-0000-000000000001'
c1='64100000-0000-0000-0000-000000000001'
c2='64100000-0000-0000-0000-000000000002'
def rpc(name,body,auth=token):
    status,result=http('/rest/v1/rpc/'+name,body,auth)
    assert status==200,(status,result)
    return result

def envelope(value):
    return {'req':{'meta':{'correlation_id':str(uuid.uuid4()),'idempotency_key':str(uuid.uuid4())},'input':value}}
def shipment(lines):
    return envelope({'order_id':order,'expected_order_version':int(sql("select version from public.orders where id='"+order+"'")),
        'worker_id':'a7000000-0000-0000-0000-000000000001','checked':True,'reason':'HTTP shipment verification',
        'lines':[{'container_id':c,'expected_version':int(sql("select version from public.containers where id='"+c+"'")),
                  'shipped_weight_kg':w} for c,w in lines]})
def cancel(result):
    return envelope({'shipment_id':result['data']['id'],'expected_version':result['data']['version'],'reason':'HTTP cancel verification'})
request=shipment([(c1,2),(c2,2)])
assert rpc('shipment_confirm',request,pending_token)['error']['code']=='AUTH_FORBIDDEN'
status,data=http('/rest/v1/rpc/shipment_confirm',request)
assert status in (401,403)
with ThreadPoolExecutor(2) as pool:
    results=list(pool.map(lambda _:rpc('shipment_confirm',request),range(2)))
assert all(r['ok'] for r in results),results
assert results[0]['data']['id']==results[1]['data']['id']
assert sum(bool(r.get('idempotent_replay')) for r in results)==1
first=results[0]
assert len(first['data']['lines'])==2
assert first['data']['total_weight_kg']==4
assert first['data']['shipping_destination_snapshot']['address']=='fixture'
second=rpc('shipment_confirm',shipment([(c1,2)]))
assert second['ok'],second
assert sql("select status from public.orders where id='"+order+"'")=='shipped'
assert rpc('shipment_cancel',cancel(first))['ok']
assert sql("select status from public.orders where id='"+order+"'")=='partially_shipped'
assert rpc('shipment_cancel',cancel(second))['ok']
assert sql("select status from public.orders where id='"+order+"'")=='in_progress'
assert Decimal(sql("select current_weight_kg from public.containers where id='"+c1+"'"))==8
assert Decimal(sql("select current_weight_kg from public.containers where id='"+c2+"'"))==4
assert sql("select count(*) from public.inventory_events where event_type='shipment'")=='3'
assert sql("select count(*) from public.inventory_events where event_type='shipment_cancel'")=='3'
assert len(rpc('shipment_container_list',{'order_id_value':order}))==2
assert len(rpc('shipment_inventory_list',{}))==2
assert len(rpc('shipment_list',{'order_id_value':order}))==2
assert rpc('shipment_get',{'shipment_id_value':first['data']['id']})['status']=='cancelled'
print('PASS: Auth + HTTP multi-line shipments, concurrent replay, full/partial states, both cancellations, stock restoration, snapshots, readers, access gates')
