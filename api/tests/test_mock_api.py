from decimal import Decimal

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app.client import iter_records
from api.app.main import KEYS, create_app

TOKEN = "fixture-test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def client():
    with TestClient(create_app(TOKEN)) as test_client:
        yield test_client


@pytest.mark.parametrize("entity", KEYS)
def test_list_paginates_in_stable_order(client, entity):
    rows = list(iter_records(client, entity, TOKEN, page_size=2))
    assert len(rows) == len({row[KEYS[entity]] for row in rows}) == 8
    assert [row["updated_at"] for row in rows] == sorted(row["updated_at"] for row in rows)


def test_nested_detail_and_payment_reconcile(client):
    response = client.get("/api/v1/orders/API-ORDER-001", headers=AUTH)
    assert response.status_code == 200
    order = response.json()
    items = order["items"]
    assert len({line["order_item_id"] for line in items}) == 2
    assert len({line["product_id"] for line in items}) == 1
    assert items[0]["discounts"][0]["discount_id"] == "WELCOME"
    total = sum(Decimal(line["line_total"]) for line in items) + Decimal(order["shipping"]["amount"])
    assert total == Decimal(order["order_total"])
    payments = list(iter_records(client, "payments", TOKEN))
    payment = next(row for row in payments if row["payment_id"] == order["payments"][0]["payment_id"])
    assert Decimal(payment["payment_amount"]) == total


def test_auth_and_missing_order(client):
    assert client.get("/api/v1/orders").status_code == 401
    assert client.get("/api/v1/orders", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/api/v1/orders/unknown", headers=AUTH).status_code == 404


def test_pagination_bounds_and_timezone(client):
    for params in ({"page": 0}, {"page_size": 101}, {"updated_since": "2025-01-01T00:00:00"}):
        assert client.get("/api/v1/orders", params=params, headers=AUTH).status_code == 422


def test_late_update_uses_inclusive_watermark(client):
    rows = list(iter_records(client, "orders", TOKEN, updated_since="2025-01-15T00:00:00Z"))
    assert [row["order_id"] for row in rows] == ["API-ORDER-001"]
    assert rows[0]["order_date"].startswith("2025-01-02")


@pytest.mark.parametrize(("scenario", "status", "delay"), [
    ("rate_limit", 429, 1), ("server_error", 500, 0.5),
])
def test_transient_errors_retry(client, scenario, status, delay):
    assert client.get("/api/v1/orders", params={"scenario": scenario}, headers=AUTH).status_code == status
    pauses = []
    assert len(list(iter_records(client, "orders", TOKEN, scenario=scenario, sleep=pauses.append))) == 8
    assert pauses == [delay]


def test_duplicate_empty_and_malformed(client):
    rows = list(iter_records(client, "orders", TOKEN, scenario="duplicate"))
    assert len(rows) == 10
    assert len({row["order_id"] for row in rows}) == 8
    assert list(iter_records(client, "orders", TOKEN, scenario="empty")) == []
    with pytest.raises(ValueError, match="Malformed orders record on page 1"):
        list(iter_records(client, "orders", TOKEN, scenario="malformed"))


def test_timeout_retries_are_bounded():
    pauses = []

    def timeout(request):
        assert request.extensions["timeout"]["read"] == 5.0
        raise httpx.ReadTimeout("simulated timeout", request=request)

    with httpx.Client(base_url="http://test", transport=httpx.MockTransport(timeout)) as client:
        with pytest.raises(httpx.ReadTimeout):
            list(iter_records(client, "orders", TOKEN, sleep=pauses.append))
    assert pauses == [0.5, 1.0]
