"""Enable anonymous sign-ins for the linked hosted Supabase project."""

import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main() -> None:
    project_ref = os.environ["SUPABASE_PROJECT_REF"]
    access_token = os.environ["SUPABASE_ACCESS_TOKEN"]
    url = f"https://api.supabase.com/v1/projects/{project_ref}/config/auth"
    request = Request(
        url,
        data=json.dumps(
            {
                "external_anonymous_users_enabled": True,
                "rate_limit_anonymous_users": 30,
            }
        ).encode(),
        method="PATCH",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            config = json.load(response)
    except (HTTPError, URLError, TimeoutError) as error:
        raise SystemExit("Failed to enable hosted anonymous sign-ins") from error

    if config.get("external_anonymous_users_enabled") is not True:
        raise SystemExit("Hosted anonymous sign-ins were not enabled")
    print("Hosted anonymous sign-ins are enabled")


if __name__ == "__main__":
    main()
