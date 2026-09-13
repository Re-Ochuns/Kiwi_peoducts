"""Issue #63 acceptance against the isolated kiwi_issue63 DB and PostgREST only.
Synthetic credentials/fixtures. Run after DB reset and pgTAP; this commits fixtures.
PostgREST must use the synthetic JWT secret below and bind 127.0.0.1:56621.
"""
import base64
import concurrent.futures
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT.parent / 'issue63-runtime'
assert 'project_id = "kiwi_issue63"' in (RUNTIME / 'supabase/config.toml').read_text()
assert 'port = 56622' in (RUNTIME / 'supabase/config.toml').read_text()
DB = 'supabase_db_kiwi_issue63'
URL = 'http://127.0.0.1:56621'
SECRET = b'issue63-local-synthetic-jwt-secret-for-acceptance-only'
MEMBER = '41000000-0000-0000-0000-000000000002'
ADMIN = '41000000-0000-0000-0000-000000000003'
PENDING = '41000000-0000-0000-0000-000000000001'

def sql(value):
    return subprocess.check_output(['docker', 'exec', '-i', DB, 'psql', '-U', 'postgres',
        '-d', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'], input=value.encode()).decode().strip()

assert sql(f"select count(*) from auth.users where id='{MEMBER}';") == '0', 'Fixture exists; reset isolated DB before rerun'
fixture = (ROOT / 'supabase/tests/00190_ripening_deadlines_test.sql').read_text()
fixture = fixture[:fixture.index('create function pg_temp.req')]
fixture = fixture.replace('select no_plan();',
    'set local search_path=public,extensions; create extension if not exists pgtap with schema extensions; select no_plan();')
sql(fixture + '\ncommit;')

def token(role, sub=None):
    def enc(data):
        return base64.urlsafe_b64encode(json.dumps(data, separators=(',', ':')).encode()).rstrip(b'=')
    payload = {'role': role, 'exp': int(time.time()) + 900}
    if sub:
        payload['sub'] = sub
    data = enc({'alg': 'HS256', 'typ': 'JWT'}) + b'.' + enc(payload)
    return (data + b'.' + base64.urlsafe_b64encode(hmac.new(SECRET, data, hashlib.sha256).digest()).rstrip(b'=')).decode()

def request(path, body=None, sub=MEMBER, role='authenticated'):
    headers = {'Authorization': 'Bearer ' + token(role, sub), 'Content-Type': 'application/json'}
    req = urllib.request.Request(URL + '/' + path, headers=headers,
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)

def envelope(value):
    return {'meta': {'idempotency_key': str(uuid.uuid4()), 'correlation_id': str(uuid.uuid4())}, 'input': value}

def rpc(name, value, sub=MEMBER):
    status, result = request('rpc/' + name, {'req': envelope(value)}, sub)
    assert status == 200, (name, status, result)
    return result

def ok(result):
    assert result['ok'], result
    return result['data']

def lot_details(lot):
    status, data = request('rpc/ripening_work_get', {'ripening_lot_id_value': lot})
    assert status == 200, data
    return data

def stamp(value):
    return value.isoformat()

rule = {'master_type': 'ripening_rule', 'harvest_year': 2025, 'harvest_month': 11,
    'variety_id': '42000000-0000-0000-0000-000000000001', 'ethylene_temperature': 20,
    'ethylene_hours': 48, 'rest_temperature': 15, 'rest_days': 3,
    'shippable_days': 5, 'best_before_days': 7}
assert rpc('master_register', rule)['error']['code'] == 'AUTH_FORBIDDEN'
master = ok(rpc('master_register', rule, ADMIN))
assert request('ripening_rules?select=id', sub=PENDING)[1] == []
assert request('ripening_rules?select=id', sub=None, role='anon')[0] in (401, 403)
assert request('rpc/ripening_deadlines_process', {})[0] in (401, 403)
assert request('ripening_rules', {key: value for key, value in rule.items() if key != 'master_type'})[0] in (401, 403)

plan = {'harvest_year': 2025, 'harvest_month': 11, 'variety_id': rule['variety_id'],
    'grade_id': 'a2000000-0000-0000-0000-000000000005', 'total_weight_kg': 8,
    'storage_location_id': '44000000-0000-0000-0000-000000000001',
    'assigned_worker_id': '43000000-0000-0000-0000-000000000001',
    'planned_ethylene_at': '2030-06-01T09:00:00+09:00', 'planned_completion_at': '2030-06-20T09:00:00+09:00',
    'allocations': [{'allocation_type': 'order', 'order_id': '47000000-0000-0000-0000-000000000001', 'allocated_weight_kg': 6},
                    {'allocation_type': 'reserve', 'allocated_weight_kg': 2}],
    'reservations': [{'container_id': '48500000-0000-0000-0000-000000000001', 'reserved_weight_kg': 8}]}
assert rpc('ripening_plan_register', dict(plan, harvest_year=2024))['error']['code'] == 'RIPENING_MASTER_NOT_FOUND'
lot = ok(rpc('ripening_plan_register', plan))['id']
ok(rpc('master_update', dict(rule, master_id=master['master_id'], expected_version=1,
    reason='Synthetic master update', ethylene_hours=72), ADMIN))
assert lot_details(lot)['master_snapshot']['ethylene_hours'] == 48
ok(rpc('ripening_plan_confirm', {'ripening_lot_id': lot, 'expected_version': lot_details(lot)['version'], 'reason': 'Synthetic confirmation'}))
now = datetime.now(timezone.utc)
base = now - timedelta(days=5, hours=1)

def work_input(lot_id, actual):
    return {'ripening_lot_id': lot_id, 'expected_version': lot_details(lot_id)['version'],
        'actual_at': stamp(actual), 'actual_temperature': 20, 'checked': True,
        'location_id': plan['storage_location_id'], 'performed_by': plan['assigned_worker_id']}

ok(rpc('ripening_ethylene_injection_complete', work_input(lot, base)))
details = lot_details(lot)
assert datetime.fromisoformat(details['calculated_rest_end_at']) == base + timedelta(days=5)
assert details['containers'][0]['current_weight_kg'] == 8
assert details['master_snapshot']['harvest_year'] == 2025
ok(rpc('ripening_ethylene_removal_complete', dict(work_input(lot, base + timedelta(days=2)), rest_temperature=15)))
assert lot_details(lot)['containers'][0]['status'] == 'awaiting_ripeness_check'
ok(rpc('ripening_ripeness_complete', work_input(lot, base + timedelta(days=5))))
container = lot_details(lot)['containers'][0]
order_id = '47000000-0000-0000-0000-000000000001'
order = request('orders?id=eq.' + order_id)[1][0]
shipment = ok(rpc('shipment_confirm', {'order_id': order_id, 'expected_order_version': order['version'],
    'worker_id': plan['assigned_worker_id'], 'checked': True, 'reason': 'Synthetic shipment',
    'lines': [{'container_id': container['id'], 'expected_version': container['version'], 'shipped_weight_kg': 2}]}))
assert lot_details(lot)['containers'][0]['current_weight_kg'] == 6
ok(rpc('shipment_cancel', {'shipment_id': shipment['id'], 'expected_version': shipment['version'], 'reason': 'Synthetic reversal'}))
assert lot_details(lot)['containers'][0]['current_weight_kg'] == 8
# Privileged deterministic clock only in the local test, not exposed to API users.
sql("select private.process_ripening_deadlines('" + stamp(now + timedelta(days=8)) + "');")
assert lot_details(lot)['containers'][0]['status'] == 'expired'
assert lot_details(lot)['containers'][0]['current_weight_kg'] == 8
assert request('orders?id=eq.' + order_id)[1][0]['needs_review']
# A second lot consumes the remaining 2kg. Historical injection must expire immediately.
second = dict(plan, total_weight_kg=2,
    allocations=[{'allocation_type': 'reserve', 'allocated_weight_kg': 2}],
    reservations=[{'container_id': '48500000-0000-0000-0000-000000000001', 'reserved_weight_kg': 2}])
lot2 = ok(rpc('ripening_plan_register', second))['id']
ok(rpc('ripening_plan_confirm', {'ripening_lot_id': lot2, 'expected_version': lot_details(lot2)['version'], 'reason': 'Synthetic confirmation'}))
req = {'req': envelope(work_input(lot2, now - timedelta(days=15)))}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    responses = list(pool.map(lambda _: request('rpc/ripening_ethylene_injection_complete', req), range(2)))
assert all(status == 200 and data['ok'] for status, data in responses), responses
assert sum(bool(data.get('idempotent_replay')) for _, data in responses) == 1
assert lot_details(lot2)['containers'][0]['status'] == 'expired'
assert lot_details(lot2)['containers'][0]['current_weight_kg'] == 2
assert sql("select count(*) from public.inventory_events where ripening_lot_id='" + lot2 + "';") == '2'
count = sql('select count(*) from public.change_history;')
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    timers = list(pool.map(lambda _: request('rpc/ripening_deadlines_process', {}, sub=None, role='service_role'), range(2)))
assert all(status == 200 and result['expired'] == 0 for status, result in timers), timers
assert sql('select count(*) from public.change_history;') == count
print('PASS: local API harvest snapshot, permission denial, injection/removal/ripeness, partial shipment/cancellation, expiry without disposal, concurrent replay and deadline rerun')
