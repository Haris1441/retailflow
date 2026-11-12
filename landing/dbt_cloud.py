"""Start a dbt Cloud job after new data lands, and wait for its result (optional).

Needs DBT_CLOUD_HOST (your account's access URL, for example https://cloud.getdbt.com),
DBT_CLOUD_ACCOUNT_ID, DBT_CLOUD_JOB_ID and DBT_CLOUD_API_TOKEN in the shell. The token is a
secret: keep it in the session environment only. API job triggers depend on the dbt Cloud plan.
"""

import os
import time

import httpx

DONE = {10: "SUCCESS", 20: "ERROR", 30: "CANCELLED"}
SETTINGS = ("DBT_CLOUD_HOST", "DBT_CLOUD_ACCOUNT_ID", "DBT_CLOUD_JOB_ID", "DBT_CLOUD_API_TOKEN")


def missing_settings():
    return [name for name in SETTINGS if not os.getenv(name)]


def run_job(cause: str, *, poll_seconds: int = 30, timeout_seconds: int = 3600, client=None) -> str:
    host = os.environ["DBT_CLOUD_HOST"].rstrip("/")
    account = os.environ["DBT_CLOUD_ACCOUNT_ID"]
    job = os.environ["DBT_CLOUD_JOB_ID"]
    headers = {"Authorization": f"Token {os.environ['DBT_CLOUD_API_TOKEN']}", "Accept": "application/json"}
    owned = client is None
    client = client or httpx.Client(timeout=30)
    try:
        response = client.post(f"{host}/api/v2/accounts/{account}/jobs/{job}/run/",
                               headers=headers, json={"cause": cause[:255]})
        response.raise_for_status()
        run_id = response.json()["data"]["id"]
        print(f"dbt Cloud run {run_id} started")
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            status = client.get(f"{host}/api/v2/accounts/{account}/runs/{run_id}/", headers=headers)
            status.raise_for_status()
            code = status.json()["data"]["status"]
            if code in DONE:
                return DONE[code]
            time.sleep(poll_seconds)
        return "TIMEOUT"
    finally:
        if owned:
            client.close()
