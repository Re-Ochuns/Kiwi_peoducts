"""Synthetic CSV acceptance. Only runs against the isolated kiwi_issue66 runtime.
Run after supabase db reset/test in issue66-runtime; commits the pgTAP fixture.
The dedicated PostgREST must listen on 127.0.0.1:56921 with SECRET below.
"""
import base64
import csv
import hashlib
import hmac
import io
import json
from pathlib import Path
import subprocess
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
DB = 'supabase_db_kiwi_issue66'
URL = 'http://127.0.0.1:56921'
SECRET = b'issue66-local-synthetic-jwt-secret-for-acceptance-only'
MEMBER = '41000000-0000-0000-0000-000000000002'

def token(sub=MEMBER):
    def enc(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b'=')
    message = enc({'alg': 'HS256', 'typ': 'JWT'}) + b'.' + enc({'role': 'authenticated', 'sub': sub, 'exp': int(time.time()) + 3600})
    return (message + b'.' + base64.urlsafe_b64encode(hmac.new(SECRET, message, hashlib.sha256).digest()).rstrip(b'=')).decode()

def sql(query):
    return subprocess.check_output(['docker', 'exec', '-i', DB, 'psql', '-U', 'postgres', '-d', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'], input=query.encode()).decode().strip()

def main():
    config = (ROOT.parent / 'issue66-runtime/supabase/config.toml').read_text()
    assert 'project_id = "kiwi_issue66"' in config and 'port = 56922' in config
    assert sql(f"select count(*) from auth.users where id='{MEMBER}'") == '0', 'Reset dedicated fixture before rerunning'
    fixture = (ROOT / 'supabase/tests/00220_business_csv_exports_test.sql').read_text().split('create function pg_temp.export')[0]
    fixture = fixture.replace('select no_plan();', 'set local search_path=public,extensions; create extension if not exists pgtap with schema extensions; select no_plan();')
    sql(fixture + '\ncommit;')
    for dataset, count in [('orders', 17), ('ripening', 38), ('shipments', 20)]:
        payload = {'req': {'meta': {'correlation_id': str(uuid.uuid4())}, 'input': {'dataset': dataset, 'filters': {}}}}
        request = urllib.request.Request(URL + '/rpc/csv_export', data=json.dumps(payload).encode(), headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=10) as response:
            result = json.load(response)
        assert result['ok'], result
        data = result['data']
        rows = list(csv.reader(io.StringIO(data['csv'].removeprefix('\ufeff'))))
        assert len(rows) == 2 and all(len(row) == count for row in rows), (dataset, rows)
        assert data['row_count'] == 1 and data['csv'].encode().startswith(b'\xef\xbb\xbf')
        assert data['csv'].endswith('\r\n')
        print(dataset, 'API CSV columns/BOM/multiline PASS')
    print('Issue66 CSV API acceptance PASS')

if __name__ == '__main__':
    main()
