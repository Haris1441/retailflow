"""Local API with opt-in deterministic failure scenarios."""

import os
from datetime import datetime
from secrets import compare_digest
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from api.fixtures.data import KEYS, build_fixtures

Entity = Literal["orders", "customers", "payments", "events", "inventory"]
Scenario = Literal["normal", "rate_limit", "server_error", "duplicate", "malformed", "empty"]
bearer = HTTPBearer(auto_error=False)


def create_app(token: str | None = None) -> FastAPI:
    app = FastAPI(title="RetailFlow mock source")
    rows = build_fixtures()

    def authenticate(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Security(bearer)],
    ) -> None:
        expected = token if token is not None else os.getenv("RETAILFLOW_API_TOKEN")
        if not expected:
            raise HTTPException(503, "Development token is not configured")
        if credentials is None or not compare_digest(
            credentials.credentials.encode(), expected.encode()
        ):
            raise HTTPException(401, "Invalid bearer token", headers={"WWW-Authenticate": "Bearer"})

    @app.get("/api/v1/orders/{order_id}", dependencies=[Depends(authenticate)])
    def order_detail(order_id: str) -> dict:
        for order in rows["orders"]:
            if order["order_id"] == order_id:
                return order
        raise HTTPException(404, "Order not found")

    @app.get("/api/v1/{entity}", dependencies=[Depends(authenticate)])
    def list_records(
        entity: Entity,
        page: Annotated[int, Query(ge=1)] = 1,
        page_size: Annotated[int, Query(ge=1, le=100)] = 3,
        updated_since: datetime | None = None,
        scenario: Scenario = "normal",
        fixture_attempt: Annotated[int, Header(alias="X-Fixture-Attempt", ge=1)] = 1,
    ) -> dict:
        if updated_since is not None and updated_since.utcoffset() is None:
            raise HTTPException(422, "updated_since must include a time zone")
        # Faults are tied to page and attempt so tests need no shared counters.
        if page == 1 and fixture_attempt == 1:
            if scenario == "rate_limit":
                raise HTTPException(429, "Simulated rate limit", headers={"Retry-After": "1"})
            if scenario == "server_error":
                raise HTTPException(500, "Simulated transient server error")

        matching = [] if scenario == "empty" else [
            row for row in rows[entity]
            if updated_since is None or datetime.fromisoformat(row["updated_at"]) >= updated_since
        ]
        matching.sort(key=lambda row: (row["updated_at"], row[KEYS[entity]]))
        start = (page - 1) * page_size
        items = matching[start:start + page_size]
        if scenario == "duplicate" and page > 1 and items:
            items = [matching[start - 1], *items]
        if scenario == "malformed" and page == 1 and items:
            items = [{**items[0], KEYS[entity]: None}, *items[1:]]
        return {
            "items": items, "page": page, "page_size": page_size,
            "next_page": page + 1 if start + page_size < len(matching) else None,
            "total_records": len(matching),
        }

    return app


app = create_app()
