"""Snowflake-backed pipeline state and watermark operations."""

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import uuid4


@dataclass(frozen=True)
class EntityConfig:
    source: str
    entity: str
    overlap_minutes: int
    max_backfill_days: int
    watermark: datetime | None

    @property
    def extraction_start(self) -> datetime | None:
        if self.watermark is None:
            return None
        return self.watermark - timedelta(minutes=self.overlap_minutes)


def new_run_id() -> str:
    return uuid4().hex


def parse_timestamp(value):
    if value is None or isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


class ControlStore:
    def __init__(self, connection, database: str):
        self.connection = connection
        self.database = database

    def get_entity(self, source: str, entity: str) -> EntityConfig:
        sql = f"""
            SELECT config.OVERLAP_MINUTES, config.MAX_BACKFILL_DAYS,
                   watermark.LAST_SUCCESSFUL_WATERMARK
            FROM {self.database}.CONTROL.ENTITY_CONFIG AS config
            LEFT JOIN {self.database}.CONTROL.WATERMARKS AS watermark
              ON config.SOURCE_SYSTEM = watermark.SOURCE_SYSTEM AND config.ENTITY = watermark.ENTITY
            WHERE config.SOURCE_SYSTEM = %s AND config.ENTITY = %s AND config.IS_ENABLED
        """
        with self.connection.cursor() as cursor:
            cursor.execute(sql, (source, entity))
            row = cursor.fetchone()
        if row is None:
            raise ValueError(f"No enabled configuration for {source}.{entity}")
        return EntityConfig(source, entity, int(row[0]), int(row[1]), parse_timestamp(row[2]))

    def start(self, run_id: str, source: str, entity: str, load_type: str) -> None:
        with self.connection.cursor() as cursor:
            cursor.execute(f"""
                INSERT INTO {self.database}.CONTROL.PIPELINE_RUNS (
                    RUN_ID, PIPELINE_NAME, SOURCE_SYSTEM, ENTITY_SCOPE, LOAD_TYPE, STATUS
                ) VALUES (%s, 'retailflow_ingestion', %s, %s, %s, 'RUNNING')
            """, (run_id, source, entity, load_type))
        self.connection.commit()

    def succeed(self, run_id: str, config: EntityConfig, watermark: datetime | None) -> None:
        with self.connection.cursor() as cursor:
            cursor.execute("BEGIN")
            try:
                cursor.execute(f"""
                    MERGE INTO {self.database}.CONTROL.WATERMARKS AS target
                    USING (SELECT %s AS source_system, %s AS entity) AS source
                    ON target.SOURCE_SYSTEM = source.source_system AND target.ENTITY = source.entity
                    WHEN MATCHED THEN UPDATE SET LAST_SUCCESSFUL_WATERMARK = %s,
                        LAST_SUCCESSFUL_RUN_ID = %s, UPDATED_AT = CURRENT_TIMESTAMP()
                    WHEN NOT MATCHED THEN INSERT (
                        SOURCE_SYSTEM, ENTITY, LAST_SUCCESSFUL_WATERMARK, LAST_SUCCESSFUL_RUN_ID
                    ) VALUES (%s, %s, %s, %s)
                """, (config.source, config.entity, watermark, run_id, config.source,
                      config.entity, watermark, run_id))
                cursor.execute(f"""
                    UPDATE {self.database}.CONTROL.PIPELINE_RUNS
                    SET STATUS = 'SUCCEEDED', FINISHED_AT = CURRENT_TIMESTAMP()
                    WHERE RUN_ID = %s AND STATUS = 'RUNNING'
                """, (run_id,))
                self.connection.commit()
            except BaseException:
                self.connection.rollback()
                raise

    def fail(self, run_id: str, message: str) -> None:
        with self.connection.cursor() as cursor:
            cursor.execute(f"""
                UPDATE {self.database}.CONTROL.PIPELINE_RUNS
                SET STATUS = 'FAILED', FINISHED_AT = CURRENT_TIMESTAMP(), ERROR_MESSAGE = %s
                WHERE RUN_ID = %s AND STATUS = 'RUNNING'
            """, (message[:4000], run_id))
        self.connection.commit()
