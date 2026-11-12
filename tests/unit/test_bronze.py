from dataclasses import replace
from unittest.mock import MagicMock

import pytest

from ingestion.bronze import load
from ingestion.sources import from_payload


@pytest.fixture
def record():
    return from_payload("MOCK_API", "orders", "delivery-1", "API-ORDER-1",
                        "API_BATCH_001", "UPSERT", None, "2025-01-15T00:00:00Z",
                        '{"order_total":"26.00","updated_at":"2025-01-15T00:00:00Z"}')


def setup_connection(*results):
    connection = MagicMock()
    cursor = connection.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect = results
    return connection, cursor


def run(connection, records):
    return load(connection, records, database="RETAIL_DWH", source="MOCK_API",
                batch="API_BATCH_001", entity="orders", chunk_size=1)


def test_repeat_delivery_and_replay(record):
    assert record.digest == replace(record, extracted_at="2026-01-01T00:00:00Z").digest
    assert record.digest != replace(record, payload='{"order_total":"27.00"}').digest
    connection, cursor = setup_connection((2, 1, None), (1, None), (0,), (1, None))
    result = run(connection, [record, record])
    assert (result.extracted, result.distinct, result.inserted, result.matched) == (2, 1, 0, 1)
    assert cursor.executemany.call_count == 2
    connection.commit.assert_called_once()
    connection.rollback.assert_not_called()
    assert "BEGIN" == cursor.execute.call_args_list[1].args[0]


def test_hash_ignores_json_object_order_but_preserves_decimal_precision(record):
    first = replace(record, payload='{"amount":0.1234567890123456789,"id":1}')
    reordered = replace(record, payload='{"id":1,"amount":0.1234567890123456789}')
    changed = replace(record, payload='{"id":1,"amount":0.1234567890123456788}')
    assert first.digest == reordered.digest
    assert first.digest != changed.digest


def test_new_delivery_inserts(record):
    connection, _ = setup_connection((1, 1, None), (0, None), (1,), (1, None))
    result = run(connection, [record])
    assert result.inserted == 1
    connection.commit.assert_called_once()


@pytest.mark.parametrize(("results", "message"), [
    ([(2, 1, 1)], "conflicting source deliveries"),
    ([(2, 1, None), (1, 1)], "different image"),
    ([(2, 1, None), (0, None), (1,), (2, None)], "reconciliation failed"),
])
def test_conflicts_rollback(record, results, message):
    connection, _ = setup_connection(*results)
    with pytest.raises(ValueError, match=message):
        run(connection, [record, record])
    connection.rollback.assert_called_once()
    connection.commit.assert_not_called()


def test_extraction_failure_rolls_back_staged_chunks(record):
    def failing_source():
        yield record
        raise RuntimeError("source failed during pagination")

    connection, cursor = setup_connection()
    with pytest.raises(RuntimeError, match="pagination"):
        run(connection, failing_source())
    cursor.executemany.assert_called_once()
    connection.rollback.assert_called_once()
    connection.commit.assert_not_called()
