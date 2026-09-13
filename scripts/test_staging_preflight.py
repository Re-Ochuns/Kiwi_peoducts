import base64
import json
import unittest
from staging_preflight import validate_config, require_success, validate_edge_secret_names


class StagingPreflightTest(unittest.TestCase):
    def setUp(self):
        self.ref = "a" * 20
        self.env = {
            "FIREBASE_PROJECT_ID": "kiwi-test-staging",
            "SUPABASE_PROJECT_REF": self.ref,
            "STAGING_SUPABASE_URL": f"https://{self.ref}.supabase.co",
            "STAGING_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            "SUPABASE_ACCESS_TOKEN": "test",
            "SUPABASE_DB_PASSWORD": "test",
            "FIREBASE_SERVICE_ACCOUNT_STAGING": json.dumps({
                "type": "service_account", "project_id": "kiwi-test-staging",
                "client_email": "test@example.test", "private_key": "test-only",
            }),
        }

    def test_accepts_public_configuration(self):
        validate_config(self.env)

    def test_missing_setting_fails(self):
        for key in self.env:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_config({k: v for k, v in self.env.items() if k != key})

    def test_wrong_project_fails(self):
        for key, value in (("STAGING_SUPABASE_URL", "https://other.supabase.co"),
                           ("FIREBASE_PROJECT_ID", "other-project")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_config({**self.env, key: value})

    def test_service_role_or_foreign_jwt_is_rejected(self):
        for role, ref in (("service_role", self.ref), ("anon", "b" * 20)):
            payload = base64.urlsafe_b64encode(json.dumps({"role": role, "ref": ref}).encode()).decode().rstrip("=")
            with self.subTest(role=role), self.assertRaises(ValueError):
                validate_config({**self.env, "STAGING_SUPABASE_PUBLISHABLE_KEY": f"header.{payload}.sig"})

    def test_legacy_anon_key(self):
        payload = base64.urlsafe_b64encode(json.dumps({"role": "anon", "ref": self.ref}).encode()).decode().rstrip("=")
        validate_config({**self.env, "STAGING_SUPABASE_PUBLISHABLE_KEY": f"header.{payload}.sig"})

    def test_new_secret_key_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_config({**self.env, "STAGING_SUPABASE_PUBLISHABLE_KEY": "sb_secret_test"})

    def test_ci_requires_matching_successful_latest_run(self):
        run = {"id": 1, "head_sha": "sha", "head_branch": "develop", "event": "push",
               "status": "completed", "conclusion": "success"}
        require_success([run], "sha")
        for runs in ([], [{**run, "head_sha": "other"}],
                     [run, {**run, "id": 2, "conclusion": "failure"}],
                     [{**run, "status": "in_progress"}],
                     [{**run, "event": "pull_request"}]):
            with self.subTest(runs=runs), self.assertRaises(ValueError):
                require_success(runs, "sha")

    def test_calendar_secrets_are_required(self):
        with self.assertRaises(ValueError):
            validate_edge_secret_names([])
        validate_edge_secret_names([{"name": name} for name in (
            "GOOGLE_CALENDAR_SERVICE_ACCOUNT", "GOOGLE_CALENDAR_ID",
            "APP_BASE_URL", "CALENDAR_SYNC_TOKEN")])


if __name__ == "__main__":
    unittest.main()
