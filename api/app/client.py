"""Bounded page extraction for the mock source."""

import os
import time
from collections.abc import Callable, Iterator

import httpx

from api.fixtures.data import KEYS

RETRYABLE = {429, 500, 502, 503, 504}


def iter_records(
    client: httpx.Client,
    entity: str,
    token: str,
    *,
    page_size: int = 3,
    updated_since: str | None = None,
    scenario: str = "normal",
    sleep: Callable[[float], None] = time.sleep,
) -> Iterator[dict]:
    key = KEYS[entity]
    page = 1
    while page <= 1000:
        params = {"page": page, "page_size": page_size, "scenario": scenario}
        if updated_since is not None:
            params["updated_since"] = updated_since
        for attempt in range(1, 4):
            try:
                response = client.get(
                    f"/api/v1/{entity}", params=params, timeout=5.0,
                    headers={"Authorization": f"Bearer {token}", "X-Fixture-Attempt": str(attempt)},
                )
                response.raise_for_status()
            except httpx.HTTPStatusError as error:
                if attempt == 3 or error.response.status_code not in RETRYABLE:
                    raise
                retry_after = error.response.headers.get("Retry-After", "")
                delay = int(retry_after) if retry_after.isascii() and retry_after.isdigit() else 0
            except httpx.TransportError:
                if attempt == 3:
                    raise
                delay = 0
            else:
                break
            sleep(min(5, max(delay, 0.5 * 2 ** (attempt - 1))))

        payload = response.json()
        records = payload["items"]
        if not isinstance(records, list) or any(
            not isinstance(row, dict) or not isinstance(row.get(key), str) or not row[key]
            for row in records
        ):
            raise ValueError(f"Malformed {entity} record on page {page}")
        yield from records
        next_page = payload["next_page"]
        if next_page is None:
            return
        if type(next_page) is not int or next_page != page + 1:
            raise ValueError(f"Invalid pagination after page {page}")
        page = next_page
    raise ValueError("Pagination exceeded 1000 pages")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entity", choices=KEYS)
    parser.add_argument("--scenario", default="normal")
    parser.add_argument("--updated-since")
    parser.add_argument("--page-size", type=int, default=3)
    args = parser.parse_args()
    token = os.getenv("RETAILFLOW_API_TOKEN")
    if not token:
        parser.error("Set RETAILFLOW_API_TOKEN first")
    with httpx.Client(base_url="http://127.0.0.1:8000") as client:
        records = list(iter_records(client, args.entity, token, page_size=args.page_size,
                                    updated_since=args.updated_since, scenario=args.scenario))
    print(f"{args.entity}: {len(records)} deliveries, "
          f"{len({row[KEYS[args.entity]] for row in records})} distinct business keys")
