import json
from datetime import datetime, timezone
from decimal import Decimal
from types import SimpleNamespace

import pytest

from landing.files import Feed, FileRejected, match_feed
from landing.processor import Landing, scan
from landing.simulator import Delivery, customer_change, new_events, product_change, write_file

PATTERN = "retailco_{}_(?P<batch_ts>[0-9]{{8}}T[0-9]{{6}})_(?P<seq>[0-9]{{3}})[.]jsonl"
FEEDS = [Feed.from_row(f"retailco_{name}", "BIGQUERY", name, PATTERN.format(name))
         for name in ("customers", "products", "customer_events")]
DELIVERY = Delivery(datetime(2025, 3, 1, 9, 0, tzinfo=timezone.utc))


class FakeRegistry:
    def __init__(self, loaded=None):
        self.rows = {}
        self.loaded = dict(loaded or {})

    def start(self, attempt):
        attempt_id = f"a{len(self.rows)}"
        self.rows[attempt_id] = {"attempt": attempt, "status": "RECEIVED"}
        return attempt_id

    def loaded_file(self, sha256):
        return self.loaded.get(sha256)

    def set_expected(self, attempt_id, expected):
        self.rows[attempt_id]["expected"] = expected

    def finish(self, attempt_id, status, *, message=None, result=None):
        self.rows[attempt_id].update(status=status, message=message, result=result)
        if status == "LOADED":
            self.loaded[self.rows[attempt_id]["attempt"].sha256] = self.rows[attempt_id]["attempt"].file_name


class FakeLoader:
    def __init__(self, error=None):
        self.calls = []
        self.error = error

    def __call__(self, records, *, source, batch, entity):
        if self.error:
            raise self.error
        records = list(records)
        self.calls.append((source, batch, entity, records))
        return SimpleNamespace(run_id="run1", extracted=len(records), distinct=len(records),
                               inserted=len(records), matched=0)


def customers_rows(count=2):
    return [customer_change(DELIVERY, 1000 + n, {"customer_id": 1000 + n, "loyalty_tier": "STANDARD",
                                                  "updated_at": "2025-01-01T00:00:00Z"})
            for n in range(count)]


def run(tmp_path, registry=None, loader=None):
    landing = Landing(tmp_path)
    registry = registry or FakeRegistry()
    loader = loader or FakeLoader()
    outcomes = scan(landing=landing, feeds=FEEDS, registry=registry, loader=loader)
    return landing, registry, loader, {outcome.file_name: outcome for outcome in outcomes}


def test_regex_identifies_feed_and_batch():
    found = match_feed("retailco_customers_20250301T090000_001.jsonl", FEEDS)
    assert (found.feed.entity, found.batch_id) == ("customers", "BATCH_20250301T090000")
    assert match_feed("retailco_customers_20250301_001.jsonl", FEEDS) is None
    assert match_feed("retailco_customers_20250301T090000_001.jsonl.bak", FEEDS) is None
    assert match_feed("retailco_orders_20250301T090000_001.jsonl", FEEDS) is None


def test_pattern_must_capture_batch_and_be_unambiguous():
    with pytest.raises(ValueError):
        Feed.from_row("bad", "BIGQUERY", "customers", "retailco_customers_.*[.]jsonl")
    twin = Feed.from_row("any", "BIGQUERY", "customers", "retailco_.*_(?P<batch_ts>[0-9]{8}T[0-9]{6})_001[.]jsonl")
    with pytest.raises(FileRejected):
        match_feed("retailco_customers_20250301T090000_001.jsonl", FEEDS + [twin])


def test_delivery_loads_and_archives(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    write_file(inbox, DELIVERY.file_name("customers"), customers_rows(3))
    landing, registry, loader, outcomes = run(tmp_path)
    outcome = outcomes[DELIVERY.file_name("customers")]
    assert (outcome.status, outcome.inserted) == ("LOADED", 3)
    source, batch, entity, records = loader.calls[0]
    assert (source, batch, entity) == ("BIGQUERY", "BATCH_20250301T090000", "customers")
    assert records[0].record_id == "BATCH_20250301T090000:customers:1000:1"
    assert json.loads(records[0].payload)["loyalty_tier"] == "SILVER"
    assert not list(inbox.iterdir())
    assert len(list(landing.folder("archive").rglob("*"))) == 3  # date folder + data + control


def test_waits_for_control_file(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    path = write_file(inbox, DELIVERY.file_name("customers"), customers_rows())
    path.with_suffix(".ctl").unlink()
    _, registry, loader, outcomes = run(tmp_path)
    assert outcomes[path.name].status == "WAITING"
    assert not registry.rows and not loader.calls and path.exists()


def test_unknown_name_is_rejected(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    (inbox / "customers_latest_FINAL.jsonl").write_text("{}\n", encoding="utf-8")
    landing, registry, loader, outcomes = run(tmp_path)
    assert outcomes["customers_latest_FINAL.jsonl"].status == "REJECTED"
    assert list(registry.rows.values())[0]["status"] == "REJECTED"
    assert (landing.folder("error") / "customers_latest_FINAL.jsonl").exists() and not loader.calls


def test_wrong_row_count_fails_without_loading(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    name = DELIVERY.file_name("customers")
    write_file(inbox, name, customers_rows(3), row_count_override=4)
    landing, registry, loader, outcomes = run(tmp_path)
    assert outcomes[name].status == "FAILED" and "promises 4 rows" in outcomes[name].message
    assert not loader.calls
    assert (landing.folder("error") / name).exists()


def test_changed_file_fails_checksum(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    path = write_file(inbox, DELIVERY.file_name("customers"), customers_rows(2))
    with path.open("a", encoding="utf-8") as handle:
        handle.write("\n")
    _, _, loader, outcomes = run(tmp_path)
    assert outcomes[path.name].status == "FAILED" and "Checksum" in outcomes[path.name].message
    assert not loader.calls


def test_same_content_is_skipped(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    name = DELIVERY.file_name("customers")
    write_file(inbox, name, customers_rows())
    landing, registry, loader, _ = run(tmp_path)
    archived = next(landing.folder("archive").rglob(name))
    (inbox / name).write_bytes(archived.read_bytes())
    (inbox / name).with_suffix(".ctl").write_bytes(archived.with_suffix(".ctl").read_bytes())
    _, _, _, outcomes = run(tmp_path, registry=registry, loader=loader)
    assert outcomes[name].status == "SKIPPED" and len(loader.calls) == 1


def test_load_failure_is_recorded_and_file_kept(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    name = DELIVERY.file_name("customers")
    write_file(inbox, name, customers_rows())
    landing, registry, _, outcomes = run(tmp_path, loader=FakeLoader(ValueError("Bronze reconciliation failed")))
    assert outcomes[name].status == "FAILED"
    assert list(registry.rows.values())[0]["message"] == "Bronze reconciliation failed"
    assert (landing.folder("error") / name).exists()


def test_bad_line_rejects_whole_file(tmp_path):
    inbox = Landing(tmp_path).folder("inbox")
    rows = customers_rows(2)
    rows[1]["entity"] = "products"
    name = DELIVERY.file_name("customers")
    write_file(inbox, name, rows)
    _, _, loader, outcomes = run(tmp_path)
    assert outcomes[name].status == "FAILED" and "Line 2" in outcomes[name].message
    assert not loader.calls


def test_interrupted_file_is_recovered(tmp_path):
    landing = Landing(tmp_path)
    name = DELIVERY.file_name("customers")
    write_file(landing.folder("processing"), name, customers_rows())
    assert set(landing.recover_interrupted()) == {name, name.replace(".jsonl", ".ctl")}
    _, _, _, outcomes = run(tmp_path)
    assert outcomes[name].status == "LOADED"


def test_simulated_changes():
    product = product_change(DELIVERY, 600, {"product_id": 600, "base_price": Decimal("19.99")})
    assert product["payload"]["base_price"] == Decimal("24.99")
    assert product["source_available_at"] == "2025-03-01T09:00:00Z"
    events = new_events(DELIVERY, [("7000", {"event_id": 7000, "customer_id": 5})] * 3, 12001,
                        datetime(2025, 2, 8, 9, 0, tzinfo=timezone.utc))
    assert [row["business_key"] for row in events] == ["12001", "12002", "12003"]
    assert events[0]["payload"]["event_timestamp"] == "2025-02-08T09:00:00Z"   # late arrival
    assert events[2]["effective_at"] == "2025-03-01T08:32:00Z"                 # on time
