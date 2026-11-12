"""Pick up landed files, validate them and load them into Bronze.

Folders under the landing root:
  inbox/       where the client (SFTP) drops data files and their .ctl control files
  processing/  a file is moved here while it is processed, so no other run takes it
  archive/     loaded or skipped files, by processing date
  error/       rejected or failed files, kept for investigation and resend
"""

import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from landing.files import (FileRejected, check_control, control_path, match_feed, read_control,
                           read_records, sha256_file)
from landing.registry import Attempt

FOLDERS = ("inbox", "processing", "archive", "error")


@dataclass(frozen=True)
class Outcome:
    file_name: str
    status: str
    message: str = ""
    inserted: int = 0


class Landing:
    def __init__(self, root: Path):
        self.root = Path(root)
        for name in FOLDERS:
            (self.root / name).mkdir(parents=True, exist_ok=True)

    def folder(self, name: str) -> Path:
        return self.root / name

    def candidates(self):
        """Data files in the inbox. A control file alone is not a candidate."""
        return sorted(path for path in self.folder("inbox").iterdir()
                      if path.is_file() and path.suffix != ".ctl" and not path.name.endswith(".part"))

    def recover_interrupted(self):
        """Files left in processing/ by a run that stopped go back to the inbox.

        Reprocessing is safe: the Bronze MERGE skips records that already landed, and only a
        LOADED registry row counts as done.
        """
        moved = []
        for path in sorted(self.folder("processing").iterdir()):
            shutil.move(path, self.folder("inbox") / path.name)
            moved.append(path.name)
        return moved

    def move(self, paths, destination: str):
        target = self.folder(destination)
        if destination == "archive":
            target = target / datetime.now(timezone.utc).strftime("%Y-%m-%d")
        target.mkdir(parents=True, exist_ok=True)
        for path in paths:
            if path.exists():
                final = target / path.name
                if final.exists():
                    final = target / f"{path.stem}.{datetime.now(timezone.utc):%H%M%S%f}{path.suffix}"
                shutil.move(path, final)


def process_file(path: Path, *, landing: Landing, feeds, registry, loader) -> Outcome:
    """One file, one attempt, one registry row. Returns WAITING if its control file is not here yet."""
    match = None
    try:
        match = match_feed(path.name, feeds)
    except FileRejected as error:
        return reject(path, landing, registry, str(error))
    if match is None:
        return reject(path, landing, registry, "File name matches no enabled feed pattern")

    control = control_path(path)
    if match.feed.requires_control and not control.exists():
        # The client writes the data file first and the control file last.
        return Outcome(path.name, "WAITING", "Control file not received yet")

    working = landing.folder("processing")
    shutil.move(path, working / path.name)
    path = working / path.name
    if control.exists():
        shutil.move(control, working / control.name)
        control = working / control.name
    files = [path, control]

    sha256 = sha256_file(path)
    attempt = registry.start(Attempt(path.name, sha256, path.stat().st_size, match.feed.name,
                                     match.feed.source_system, match.feed.entity, match.batch_id))
    try:
        already = registry.loaded_file(sha256)
        if already:
            registry.finish(attempt, "SKIPPED", message=f"Identical content already loaded as {already}")
            landing.move(files, "archive")
            return Outcome(path.name, "SKIPPED", f"already loaded as {already}")

        expected = None
        if control.exists():
            promised = read_control(control)
            check_control(promised, path, sha256)
            expected = promised.row_count
        registry.set_expected(attempt, expected)
        records = read_records(path, match, expected)
        result = loader(records, source=match.feed.source_system, batch=match.batch_id,
                        entity=match.feed.entity)
    except Exception as error:  # every failure is recorded, then the file goes to error/
        registry.finish(attempt, "FAILED", message=str(error))
        landing.move(files, "error")
        return Outcome(path.name, "FAILED", str(error))

    registry.finish(attempt, "LOADED", result=result)
    landing.move(files, "archive")
    return Outcome(path.name, "LOADED", f"run {result.run_id}", result.inserted)


def reject(path: Path, landing: Landing, registry, message: str) -> Outcome:
    sha256 = sha256_file(path)
    attempt = registry.start(Attempt(path.name, sha256, path.stat().st_size))
    registry.finish(attempt, "REJECTED", message=message)
    landing.move([path, control_path(path)], "error")
    return Outcome(path.name, "REJECTED", message)


def scan(*, landing: Landing, feeds, registry, loader):
    """One pass over the inbox: what an event trigger or a sensor tick runs."""
    return [process_file(path, landing=landing, feeds=feeds, registry=registry, loader=loader)
            for path in landing.candidates()]
