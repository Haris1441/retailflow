"""Source records and the Phase 5 fixture adapters."""

import hashlib
import json
import re
import simplejson
from dataclasses import dataclass
from datetime import datetime, timezone

from api.app.client import iter_records
from api.fixtures.data import KEYS as API_KEYS

BIGQUERY_KEYS = {
    "categories": "category_id", "brands": "brand_id", "suppliers": "supplier_id",
    "stores": "store_id", "customers": "customer_id", "products": "product_id",
    "promotions": "promotion_id", "exchange_rates": "FORMAT('%t:%s:%s', rate_date, from_currency, to_currency)",
    "order_items": "order_item_id", "orders": "order_id",
    "order_promotions": "order_promotion_id", "payments": "payment_id",
    "inventory": "inventory_id", "returns": "return_id", "customer_events": "event_id",
}
BASELINE_COUNTS = dict(zip(BIGQUERY_KEYS, (
    9, 25, 20, 12, 5000, 1000, 3, 168, 50000, 20000, 2000, 20800, 8400, 500, 12000,
), strict=True))
CHANGE_COUNTS = dict(zip(range(2, 9), (6070, 1020, 4, 260, 302, 20, 2), strict=True))
EVENT_FIELDS = ("event_timestamp", "order_date", "payment_timestamp", "requested_at", "applied_at", "created_at")


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class Record:
    source: str
    entity: str
    record_id: str
    business_key: str
    batch: str
    operation: str
    event_at: str | None
    updated_at: str | None
    effective_at: str | None
    available_at: str
    extracted_at: str
    payload: str

    @property
    def digest(self) -> str:
        # Extraction time changes on every attempt. Source metadata must not.
        metadata = (self.business_key, self.batch, self.operation, self.event_at,
                    self.updated_at, self.effective_at, self.available_at,
                    simplejson.loads(self.payload, use_decimal=True))
        return hashlib.sha256(simplejson.dumps(metadata, sort_keys=True, use_decimal=True).encode()).hexdigest()


def from_payload(source, entity, record_id, business_key, batch, operation,
                 effective_at, available_at, payload) -> Record:
    parsed = json.loads(payload)
    if not isinstance(parsed, dict) or not record_id or not business_key or not available_at:
        raise ValueError(f"Invalid envelope for {source}.{entity}")
    event_at = next((parsed[field] for field in EVENT_FIELDS if parsed.get(field)), None)
    return Record(source, entity, record_id, business_key, batch, operation, event_at,
                  parsed.get("updated_at"), effective_at, available_at, now(), payload)


def checked_rows(result, label, expected):
    if result.total_rows != expected:
        raise ValueError(f"{label}: expected {expected} rows, found {result.total_rows}")
    count = 0
    for row in result:
        count += 1
        yield row
    if count != expected:
        raise ValueError(f"{label}: expected {expected} deliveries, extracted {count}")


def bigquery_records(client, project, dataset, location, batch, entity, max_bytes):
    if not re.fullmatch(r"[a-z][a-z0-9-]*", project) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", dataset):
        raise ValueError("Invalid BigQuery project or dataset identifier")
    from google.cloud import bigquery

    config = bigquery.QueryJobConfig(maximum_bytes_billed=max_bytes)
    prefix = f"`{project}.{dataset}."
    if batch == "BATCH_001":
        for name in (entity,) if entity else BIGQUERY_KEYS:
            key = BIGQUERY_KEYS[name]
            sql = f"""
                SELECT source_record_id, CAST({key} AS STRING) AS business_key,
                       source_operation, source_available_at,
                       TO_JSON_STRING((SELECT AS STRUCT t.* EXCEPT
                           (source_record_id, batch_id, source_operation, source_available_at))) AS payload
                FROM {prefix}{name}` AS t
                WHERE batch_id = 'BATCH_001'
            """
            result = client.query(sql, job_config=config, location=location).result(page_size=1000)
            for row in checked_rows(result, name, BASELINE_COUNTS[name]):
                yield from_payload("BIGQUERY", name, row.source_record_id, row.business_key,
                                   batch, row.source_operation, None,
                                   row.source_available_at.isoformat(), row.payload)
        return

    suffix = batch.removeprefix("BATCH_")
    sql = f"""
        SELECT entity, source_record_id, business_key, operation, effective_at,
               source_available_at, TO_JSON_STRING(payload) AS payload
        FROM {prefix}changes_{suffix}`
    """
    result = client.query(sql, job_config=config, location=location).result(page_size=1000)
    for row in checked_rows(result, batch, CHANGE_COUNTS[int(suffix)]):
        yield from_payload("BIGQUERY", row.entity, row.source_record_id, row.business_key,
                           batch, row.operation, row.effective_at.isoformat(),
                           row.source_available_at.isoformat(), row.payload)


def api_records(client, token, entity, scenario):
    for name in (entity,) if entity else API_KEYS:
        rows = list(iter_records(client, name, token, scenario=scenario))
        keys = {row[API_KEYS[name]] for row in rows}
        if len(keys) != 8 or len(rows) != (10 if scenario == "duplicate" else 8):
            raise ValueError(f"Unexpected delivery count for API {name}")
        for row in rows:
            key = row[API_KEYS[name]]
            updated = row["updated_at"]
            payload = json.dumps(row, sort_keys=True, separators=(",", ":"), allow_nan=False)
            yield from_payload("MOCK_API", name, f"{key}:{updated}", key, "API_BATCH_001",
                               "UPSERT", None, updated, payload)
