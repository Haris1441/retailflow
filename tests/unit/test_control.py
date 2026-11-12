from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from pipeline.control import ControlStore, EntityConfig, parse_timestamp


def connection_with_rows(*rows):
    connection = MagicMock()
    cursor = connection.cursor.return_value.__enter__.return_value
    cursor.fetchone.side_effect = rows
    return connection, cursor


def test_watermark_overlap_is_inclusive():
    config = EntityConfig(
        "MOCK_API", "orders", 60, 45,
        datetime(2025, 1, 15, 0, 0, tzinfo=timezone.utc),
    )
    assert config.extraction_start == datetime(2025, 1, 14, 23, 0, tzinfo=timezone.utc)
    assert EntityConfig("MOCK_API", "orders", 60, 45, None).extraction_start is None


def test_get_entity_loads_configuration():
    connection, cursor = connection_with_rows((60, 45, "2025-01-15T00:00:00Z"))
    store = ControlStore(connection, "RETAIL_DWH")
    config = store.get_entity("MOCK_API", "orders")
    assert config.overlap_minutes == 60
    assert config.watermark == datetime(2025, 1, 15, tzinfo=timezone.utc)
    assert cursor.execute.call_args.args[1] == ("MOCK_API", "orders")


def test_missing_entity_configuration_fails():
    connection, _ = connection_with_rows(None)
    with pytest.raises(ValueError, match="No enabled configuration"):
        ControlStore(connection, "RETAIL_DWH").get_entity("MOCK_API", "orders")


def test_success_updates_watermark_and_run_atomically():
    connection, cursor = connection_with_rows()
    store = ControlStore(connection, "RETAIL_DWH")
    config = EntityConfig("MOCK_API", "orders", 60, 45, None)
    store.succeed("run-1", config, datetime(2025, 1, 15, tzinfo=timezone.utc))
    assert cursor.execute.call_args_list[0].args[0] == "BEGIN"
    assert connection.commit.call_count == 1
    connection.rollback.assert_not_called()


def test_failed_control_update_rolls_back():
    connection, cursor = connection_with_rows()
    cursor.execute.side_effect = [None, RuntimeError("database unavailable")]
    store = ControlStore(connection, "RETAIL_DWH")
    with pytest.raises(RuntimeError, match="unavailable"):
        store.succeed("run-1", EntityConfig("MOCK_API", "orders", 60, 45, None), None)
    connection.rollback.assert_called_once()
    connection.commit.assert_not_called()


def test_parse_timestamp_accepts_database_and_iso_values():
    moment = datetime(2025, 1, 15, tzinfo=timezone.utc)
    assert parse_timestamp(None) is None
    assert parse_timestamp(moment) is moment
    assert parse_timestamp("2025-01-15T00:00:00Z") == moment
