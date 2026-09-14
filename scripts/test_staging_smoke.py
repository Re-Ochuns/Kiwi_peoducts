import json
import unittest
from urllib.parse import urlparse, parse_qs
from uuid import UUID
from unittest.mock import patch
import staging_smoke


class SmokeTest(unittest.TestCase):
    def setUp(self):
        self.env = {"FIREBASE_PROJECT_ID": "kiwi-staging", "GITHUB_SHA": "expected",
                    "STAGING_SUPABASE_URL": "https://staging.supabase.co",
                    "STAGING_SUPABASE_PUBLISHABLE_KEY": "public-test"}
        self.responses = [
            (200, json.dumps({"commit": "expected"}).encode()),
            (200, b'<script src="flutter_bootstrap.js"></script>'),
            (200, b'<script src="flutter_bootstrap.js"></script>'),
            (401, b'{}'), (401, b''), (200, b'[]'),
        ]

    def test_success(self):
        with patch.object(staging_smoke, "get", side_effect=self.responses) as get:
            staging_smoke.run(self.env)
        pdf_url = get.call_args_list[3].args[0]
        query = parse_qs(urlparse(pdf_url).query)
        self.assertEqual(UUID(query["container_id"][0]).version, 4)
        self.assertEqual(get.call_args_list[4].kwargs.get("method"), "POST")

    def test_wrong_commit_and_public_endpoints_fail(self):
        for index, response in ((0, (200, b'{"commit":"old"}')),
                                (2, (404, b'not found')),
                                (3, (200, b'pdf')),
                                (4, (200, b'{}')),
                                (5, (200, b'[{"id":"private"}]'))):
            responses = list(self.responses)
            responses[index] = response
            with self.subTest(index=index):
                with patch.object(staging_smoke, "get", side_effect=responses):
                    with self.assertRaises(ValueError):
                        staging_smoke.run(self.env)


if __name__ == "__main__":
    unittest.main()
