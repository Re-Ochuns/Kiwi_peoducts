"""Post-deploy read-only probes. No credentials or response bodies are logged."""
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def get(url, headers=None, method="GET"):
    try:
        with urlopen(Request(url, headers=headers or {}, method=method, data=b"{}" if method == "POST" else None), timeout=30) as response:
            return response.status, response.read()
    except HTTPError as error:
        return error.code, error.read()


def run(env):
    base = f'https://{env["FIREBASE_PROJECT_ID"]}.web.app'
    status, data = get(base + "/deployment.json?commit=" + env["GITHUB_SHA"], {"Cache-Control": "no-cache"})
    if status != 200 or json.loads(data).get("commit") != env["GITHUB_SHA"]:
        raise ValueError("Hosting does not serve this deployment commit")
    for path in ("/", "/work-tasks/staging-route-probe"):
        status, data = get(base + path)
        if status != 200 or b"flutter_bootstrap.js" not in data:
            raise ValueError("Hosting SPA fallback failed")
    api = env["STAGING_SUPABASE_URL"]
    # The handler validates container_id before checking authentication.
    status, _ = get(api + "/functions/v1/label-pdf?container_id=00000000-0000-4000-8000-000000000000")
    if status != 401:
        raise ValueError("Unauthenticated PDF request must be rejected")
    status, _ = get(api + "/functions/v1/calendar-sync", {"Content-Type": "application/json"}, method="POST")
    if status != 401:
        raise ValueError("Calendar endpoint is missing or unexpectedly public")
    status, data = get(api + "/rest/v1/profiles?select=id", {
        "apikey": env["STAGING_SUPABASE_PUBLISHABLE_KEY"],
    })
    if status not in (401, 403) and not (status == 200 and json.loads(data) == []):
        raise ValueError("Anonymous request returned protected profiles")
    print("Hosting identity, SPA routing, and anonymous boundaries passed")


if __name__ == "__main__":
    try:
        run(os.environ)
    except (ValueError, KeyError, OSError, URLError):
        print("Staging smoke test failed; inspect Hosting/Auth/Edge configuration (response bodies omitted).", file=sys.stderr)
        sys.exit(1)
