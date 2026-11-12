"""Plays the client: writes change files into the inbox, the way an SFTP upload would.

The payloads are built from records already in Bronze, so they match the client's schema
exactly. A delivery holds three files:
  customers        loyalty tier changes (SCD Type 2 and Type 3 history)
  products         base price +5 (SCD Type 2 history, no effect on past sales)
  customer_events  new events, two of them backdated (late-arriving, incremental Silver)
"""

import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

import simplejson

from landing.files import CONTROL_SUFFIX, sha256_file

NEXT_TIER = {"STANDARD": "SILVER", "SILVER": "GOLD", "GOLD": "SILVER"}
# Templates come from records delivered once and never changed, above the ID ranges that the
# Phase 3 defect scenarios use, so a simulated change is a clean change.
TEMPLATE_FLOOR = {"customers": 1000, "products": 500, "customer_events": 6000}


@dataclass(frozen=True)
class Delivery:
    at: datetime

    @property
    def stamp(self) -> str:
        return self.at.strftime("%Y%m%dT%H%M%S")

    @property
    def batch_id(self) -> str:
        return f"BATCH_{self.stamp}"

    def file_name(self, entity: str, seq: int = 1) -> str:
        return f"retailco_{entity}_{self.stamp}_{seq:03}.jsonl"


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def envelope(delivery: Delivery, entity, business_key, operation, effective_at, payload):
    return {
        "entity": entity,
        "source_record_id": f"{delivery.batch_id}:{entity}:{business_key}:1",
        "business_key": str(business_key),
        "operation": operation,
        "effective_at": iso(effective_at),
        "source_available_at": iso(delivery.at),
        "payload": payload,
    }


def customer_change(delivery: Delivery, business_key, payload):
    changed = dict(payload, loyalty_tier=NEXT_TIER.get(str(payload.get("loyalty_tier")).upper(), "SILVER"),
                   updated_at=iso(delivery.at))
    return envelope(delivery, "customers", business_key, "UPDATE", delivery.at, changed)


def product_change(delivery: Delivery, business_key, payload):
    changed = dict(payload, base_price=Decimal(str(payload["base_price"])) + Decimal("5"),
                   updated_at=iso(delivery.at))
    return envelope(delivery, "products", business_key, "UPDATE", delivery.at, changed)


def new_events(delivery: Delivery, templates, first_event_id: int, backdated: datetime):
    rows = []
    for offset, (_, payload) in enumerate(templates):
        event_id = first_event_id + offset
        # The first two are late arrivals: their business time is weeks before they arrive.
        happened = backdated if offset < 2 else delivery.at - timedelta(minutes=30 - offset)
        event = dict(payload, event_id=event_id, event_timestamp=iso(happened))
        rows.append(envelope(delivery, "customer_events", event_id, "INSERT", happened, event))
    return rows


def write_file(inbox: Path, name: str, rows, *, row_count_override: int | None = None) -> Path:
    """Write the data file atomically (temporary name, then rename), then the control file."""
    path = inbox / name
    partial = inbox / f"{name}.part"
    with partial.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(simplejson.dumps(row, use_decimal=True, sort_keys=True, separators=(",", ":")) + "\n")
    os.replace(partial, path)
    write_control(path, len(rows) if row_count_override is None else row_count_override)
    return path


def write_control(path: Path, row_count: int) -> Path:
    control = path.with_suffix(CONTROL_SUFFIX)
    control.write_text(json.dumps({
        "file_name": path.name, "row_count": row_count, "sha256": sha256_file(path),
        "created_at": iso(datetime.now(timezone.utc)),
    }, indent=2), encoding="utf-8")
    return control


class BronzeTemplates:
    """Reads the client's current records from Bronze. Only the simulator does this."""

    def __init__(self, connection, database: str):
        self.connection = connection
        self.table = f"{database}.BRONZE.SOURCE_RECORDS"

    def _rows(self, sql, params):
        with self.connection.cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.fetchall()

    def next_delivery(self) -> Delivery:
        latest = self._rows(f"SELECT MAX(SOURCE_AVAILABLE_AT) FROM {self.table} WHERE SOURCE_SYSTEM = %s",
                            ("BIGQUERY",))[0][0]
        day = (latest.astimezone(timezone.utc) + timedelta(days=1)).date()
        return Delivery(datetime(day.year, day.month, day.day, 9, 0, tzinfo=timezone.utc))

    def unchanged(self, entity: str, count: int):
        rows = self._rows(f"""
            SELECT BUSINESS_KEY, RAW_PAYLOAD FROM {self.table}
            WHERE SOURCE_SYSTEM = 'BIGQUERY' AND ENTITY = %s
            QUALIFY COUNT(*) OVER (PARTITION BY BUSINESS_KEY) = 1
                AND TRY_TO_NUMBER(BUSINESS_KEY) >= %s
            ORDER BY TRY_TO_NUMBER(BUSINESS_KEY)
            LIMIT %s
        """, (entity, TEMPLATE_FLOOR[entity], count))
        return [(key, simplejson.loads(payload, use_decimal=True)) for key, payload in rows]

    def max_event_id(self) -> int:
        return int(self._rows(f"""
            SELECT MAX(TRY_TO_NUMBER(BUSINESS_KEY)) FROM {self.table}
            WHERE SOURCE_SYSTEM = 'BIGQUERY' AND ENTITY = 'customer_events'
        """, ())[0][0])


def build_delivery(templates: BronzeTemplates, delivery: Delivery | None = None):
    """Rows per file name for one normal delivery."""
    delivery = delivery or templates.next_delivery()
    events = templates.unchanged("customer_events", 5)
    return delivery, {
        delivery.file_name("customers"): [customer_change(delivery, key, payload)
                                          for key, payload in templates.unchanged("customers", 3)],
        delivery.file_name("products"): [product_change(delivery, key, payload)
                                         for key, payload in templates.unchanged("products", 2)],
        delivery.file_name("customer_events"): new_events(delivery, events, templates.max_event_id() + 1,
                                                          delivery.at - timedelta(days=21)),
    }
