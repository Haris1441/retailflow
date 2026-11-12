"""Snowflake-backed feed configuration and file registry."""

from dataclasses import dataclass
from uuid import uuid4

from landing.files import Feed


@dataclass(frozen=True)
class Attempt:
    file_name: str
    sha256: str
    size_bytes: int
    feed_name: str | None = None
    source_system: str | None = None
    entity: str | None = None
    batch_id: str | None = None


class SnowflakeRegistry:
    def __init__(self, connection, database: str):
        self.connection = connection
        self.table = f"{database}.CONTROL.FILE_REGISTRY"
        self.config = f"{database}.CONTROL.FILE_CONFIG"

    def _run(self, sql, params=()):
        with self.connection.cursor() as cursor:
            cursor.execute(sql, params)
            rows = cursor.fetchall() if cursor.description else []
        self.connection.commit()
        return rows

    def feeds(self):
        rows = self._run(f"""
            SELECT FEED_NAME, SOURCE_SYSTEM, ENTITY, FILE_PATTERN, REQUIRES_CONTROL_FILE
            FROM {self.config} WHERE IS_ENABLED ORDER BY FEED_NAME
        """)
        return [Feed.from_row(*row) for row in rows]

    def start(self, attempt: Attempt) -> str:
        attempt_id = uuid4().hex
        self._run(f"""
            INSERT INTO {self.table} (ATTEMPT_ID, FILE_NAME, FILE_SHA256, FILE_SIZE_BYTES, FEED_NAME,
                                      SOURCE_SYSTEM, ENTITY, BATCH_ID, STATUS)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'RECEIVED')
        """, (attempt_id, attempt.file_name, attempt.sha256, attempt.size_bytes, attempt.feed_name,
              attempt.source_system, attempt.entity, attempt.batch_id))
        return attempt_id

    def loaded_file(self, sha256: str) -> str | None:
        rows = self._run(f"""
            SELECT FILE_NAME FROM {self.table}
            WHERE FILE_SHA256 = %s AND STATUS = 'LOADED'
            ORDER BY FINISHED_AT LIMIT 1
        """, (sha256,))
        return rows[0][0] if rows else None

    def set_expected(self, attempt_id: str, expected_rows: int | None) -> None:
        self._run(f"UPDATE {self.table} SET EXPECTED_ROWS = %s WHERE ATTEMPT_ID = %s",
                  (expected_rows, attempt_id))

    def finish(self, attempt_id: str, status: str, *, message: str | None = None, result=None) -> None:
        counts = (result.extracted, result.inserted, result.matched, result.run_id) if result else (None,) * 4
        self._run(f"""
            UPDATE {self.table}
            SET STATUS = %s, ERROR_MESSAGE = %s, EXTRACTED_ROWS = %s, INSERTED_ROWS = %s,
                MATCHED_ROWS = %s, RUN_ID = %s, FINISHED_AT = CURRENT_TIMESTAMP()
            WHERE ATTEMPT_ID = %s
        """, (status, message[:4000] if message else None, *counts, attempt_id))

    def recent(self, limit: int = 20):
        return self._run(f"""
            SELECT DETECTED_AT, FILE_NAME, FEED_NAME, BATCH_ID, STATUS, EXPECTED_ROWS, INSERTED_ROWS,
                   MATCHED_ROWS, ERROR_MESSAGE
            FROM {self.table} ORDER BY DETECTED_AT DESC LIMIT %s
        """, (limit,))
