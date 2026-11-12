"""File contract: feed patterns, control files and the JSONL record envelope."""

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

import simplejson

from ingestion.sources import from_payload

OPERATIONS = {"INSERT", "UPDATE", "DELETE"}
ENVELOPE = ("entity", "source_record_id", "business_key", "operation", "effective_at",
            "source_available_at", "payload")
CONTROL_SUFFIX = ".ctl"


@dataclass(frozen=True)
class Feed:
    name: str
    source_system: str
    entity: str
    pattern: re.Pattern
    requires_control: bool = True

    @classmethod
    def from_row(cls, name, source_system, entity, pattern, requires_control=True):
        compiled = re.compile(pattern)
        if "batch_ts" not in compiled.groupindex:
            raise ValueError(f"Feed {name}: the pattern must capture the group batch_ts")
        return cls(name, source_system, entity, compiled, bool(requires_control))


@dataclass(frozen=True)
class Match:
    feed: Feed
    batch_id: str


@dataclass(frozen=True)
class ControlFile:
    file_name: str
    row_count: int
    sha256: str


class FileRejected(Exception):
    """The file cannot be processed as delivered. Nothing is loaded."""


def match_feed(file_name: str, feeds) -> Match | None:
    """Identify the feed by regex on the whole file name. The batch ID comes from the name."""
    hits = [(feed, found) for feed in feeds if (found := feed.pattern.fullmatch(file_name))]
    if not hits:
        return None
    if len(hits) > 1:
        names = ", ".join(feed.name for feed, _ in hits)
        raise FileRejected(f"File name matches more than one feed: {names}")
    feed, found = hits[0]
    return Match(feed, f"BATCH_{found['batch_ts']}")


def control_path(data_path: Path) -> Path:
    return data_path.with_suffix(CONTROL_SUFFIX)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def read_control(path: Path) -> ControlFile:
    try:
        body = json.loads(path.read_text(encoding="utf-8"))
        return ControlFile(str(body["file_name"]), int(body["row_count"]), str(body["sha256"]).lower())
    except (ValueError, KeyError, TypeError) as error:
        raise FileRejected(f"Unreadable control file {path.name}: {error}") from error


def check_control(control: ControlFile, data_path: Path, sha256: str) -> None:
    if control.file_name != data_path.name:
        raise FileRejected(f"Control file names {control.file_name}, not {data_path.name}")
    if control.sha256 != sha256:
        raise FileRejected("Checksum differs from the control file: the file is incomplete or changed")


def read_records(data_path: Path, match: Match, expected_rows: int | None):
    """Parse every line into a Bronze record. Any bad line rejects the whole file."""
    records = []
    with data_path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = simplejson.loads(line, use_decimal=True)
                missing = [field for field in ENVELOPE if field not in row]
                if missing:
                    raise ValueError(f"missing {', '.join(missing)}")
                if row["entity"] != match.feed.entity:
                    raise ValueError(f"entity {row['entity']} does not belong to feed {match.feed.name}")
                if row["operation"] not in OPERATIONS:
                    raise ValueError(f"unknown operation {row['operation']}")
                payload = simplejson.dumps(row["payload"], sort_keys=True, use_decimal=True,
                                           separators=(",", ":"))
                records.append(from_payload(
                    match.feed.source_system, row["entity"], str(row["source_record_id"]),
                    str(row["business_key"]), match.batch_id, row["operation"],
                    row["effective_at"], row["source_available_at"], payload,
                ))
            except (ValueError, TypeError) as error:
                raise FileRejected(f"Line {number}: {error}") from error
    if not records:
        raise FileRejected("The file has no records")
    if expected_rows is not None and len(records) != expected_rows:
        raise FileRejected(f"Control file promises {expected_rows} rows, the file has {len(records)}")
    return records
