"""Fail closed before a staging build or any remote mutation. Never print secrets."""
import base64
import json
import os
import re
import subprocess
import sys


def validate_config(env):
    required = (
        "FIREBASE_PROJECT_ID", "SUPABASE_PROJECT_REF", "STAGING_SUPABASE_URL",
        "STAGING_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ACCESS_TOKEN",
        "SUPABASE_DB_PASSWORD", "FIREBASE_SERVICE_ACCOUNT_STAGING",
    )
    for name in required:
        if not env.get(name, "").strip():
            raise ValueError(f"Missing configuration: {name}")
    project = env["FIREBASE_PROJECT_ID"]
    ref = env["SUPABASE_PROJECT_REF"]
    if not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", project):
        raise ValueError("Invalid FIREBASE_PROJECT_ID")
    if not re.fullmatch(r"[a-z]{20}", ref):
        raise ValueError("Invalid SUPABASE_PROJECT_REF")
    if env["STAGING_SUPABASE_URL"] != f"https://{ref}.supabase.co":
        raise ValueError("SUPABASE_URL does not match SUPABASE_PROJECT_REF")
    key = env["STAGING_SUPABASE_PUBLISHABLE_KEY"]
    if not key.startswith("sb_publishable_"):
        try:
            parts = key.split(".")
            if len(parts) != 3:
                raise ValueError()
            payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
        except (ValueError, TypeError, UnicodeError):
            raise ValueError("Expected a publishable key or legacy anon JWT") from None
        if not isinstance(payload, dict) or payload.get("role") != "anon" or payload.get("ref") != ref:
            raise ValueError("Legacy key must be anon and belong to staging")
    try:
        account = json.loads(env["FIREBASE_SERVICE_ACCOUNT_STAGING"])
        valid = (
            account.get("type") == "service_account"
            and account.get("project_id") == project
            and bool(account.get("client_email"))
            and bool(account.get("private_key"))
        )
    except (ValueError, AttributeError):
        valid = False
    if not valid:
        raise ValueError("Firebase service account is invalid or belongs to another project")


def require_success(runs, sha):
    candidates = [
        run for run in runs if run.get("head_sha") == sha
        and run.get("head_branch") == "develop" and run.get("event") == "push"
    ]
    if not candidates:
        raise ValueError("No develop push CI run exists for the deployment commit")
    latest = max(candidates, key=lambda run: run["id"])
    if latest.get("status") != "completed" or latest.get("conclusion") != "success":
        raise ValueError("Latest CI run for the deployment commit has not succeeded")


def check_ci(env):
    if env.get("GITHUB_REF") != "refs/heads/develop":
        raise ValueError("Staging deploys must run from develop")
    sha = env.get("GITHUB_SHA", "")
    repo = env.get("GITHUB_REPOSITORY", "")
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        raise ValueError("Invalid deployment source")
    for workflow in ("flutter-ci.yml", "database-ci.yml"):
        endpoint = f"repos/{repo}/actions/workflows/{workflow}/runs?head_sha={sha}&event=push&per_page=100"
        result = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True, check=True)
        require_success(json.loads(result.stdout)["workflow_runs"], sha)
        print(f"{workflow}: deployment commit passed")


def validate_edge_secret_names(rows):
    names = {row["name"] for row in rows}
    required = {"GOOGLE_CALENDAR_SERVICE_ACCOUNT", "GOOGLE_CALENDAR_ID", "APP_BASE_URL", "CALENDAR_SYNC_TOKEN"}
    missing = sorted(required - names)
    if missing:
        raise ValueError("Missing Edge Function secrets: " + ", ".join(missing))


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["ci"]:
            check_ci(os.environ)
        elif len(sys.argv) == 3 and sys.argv[1] == "edge-secrets":
            with open(sys.argv[2], encoding="utf-8") as source:
                validate_edge_secret_names(json.load(source))
        elif not sys.argv[1:]:
            validate_config(os.environ)
            print("Staging configuration validated (secret values omitted)")
        else:
            raise ValueError("Usage: staging_preflight.py [ci | edge-secrets FILE]")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError):
        # Do not echo HTTP bodies, subprocess stderr, env values, or JSON payloads.
        print("Staging preflight failed. Check required configuration and CI status; secret values omitted.", file=sys.stderr)
        sys.exit(1)
