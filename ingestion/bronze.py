"""Transactional Bronze loading for one fixture scope at a time."""

import re
from dataclasses import dataclass
from itertools import batched
from uuid import uuid4

COLUMNS = """
SOURCE_SYSTEM, ENTITY, SOURCE_RECORD_ID, BUSINESS_KEY, BATCH_ID, SOURCE_OPERATION,
SOURCE_EVENT_AT, SOURCE_UPDATED_AT, SOURCE_EFFECTIVE_AT, SOURCE_AVAILABLE_AT,
EXTRACTED_AT, RUN_ID, RECORD_HASH, RAW_PAYLOAD
"""
IDENTITY = """
t.SOURCE_SYSTEM = s.SOURCE_SYSTEM AND t.ENTITY = s.ENTITY
AND t.SOURCE_RECORD_ID = s.SOURCE_RECORD_ID
"""


@dataclass(frozen=True)
class LoadResult:
    run_id: str
    extracted: int
    distinct: int
    inserted: int
    matched: int


def stage_values(record, run_id):
    return (
        record.source, record.entity, record.record_id, record.business_key,
        record.batch, record.operation, record.event_at, record.updated_at,
        record.effective_at, record.available_at, record.extracted_at, run_id,
        record.digest, record.payload,
    )


def load(connection, records, *, database, source, batch, entity, chunk_size=250):
    if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", database):
        raise ValueError("Use an unquoted uppercase Snowflake database identifier")
    if not 1 <= chunk_size <= 500:
        raise ValueError("chunk_size must be between 1 and 500")

    run_id = uuid4().hex
    target = f"{database}.BRONZE.SOURCE_RECORDS"
    stage = f"{database}.BRONZE.TMP_BRONZE_{run_id.upper()}"
    audit = f"{database}.AUDIT.BRONZE_LOAD_RUNS"
    unique_stage = f"""
        SELECT * FROM {stage}
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY SOURCE_SYSTEM, ENTITY, SOURCE_RECORD_ID
            ORDER BY EXTRACTED_AT
        ) = 1
    """
    with connection.cursor() as cursor:
        # Snowflake DDL commits implicitly. Create the session-scoped table first.
        cursor.execute(f"""
            CREATE TEMPORARY TABLE {stage} (
                SOURCE_SYSTEM VARCHAR, ENTITY VARCHAR, SOURCE_RECORD_ID VARCHAR,
                BUSINESS_KEY VARCHAR, BATCH_ID VARCHAR, SOURCE_OPERATION VARCHAR,
                SOURCE_EVENT_AT VARCHAR, SOURCE_UPDATED_AT VARCHAR, SOURCE_EFFECTIVE_AT VARCHAR,
                SOURCE_AVAILABLE_AT VARCHAR, EXTRACTED_AT VARCHAR, RUN_ID VARCHAR,
                RECORD_HASH VARCHAR, RAW_PAYLOAD VARCHAR
            )
        """)
        cursor.execute("BEGIN")
        try:
            extracted = 0
            placeholders = ", ".join(["%s"] * 14)
            for chunk in batched(records, chunk_size):
                if any(row.source != source or row.batch != batch or
                       (entity and row.entity != entity) for row in chunk):
                    raise ValueError("Extracted record falls outside the requested load scope")
                cursor.executemany(
                    f"INSERT INTO {stage} ({COLUMNS}) VALUES ({placeholders})",
                    [stage_values(row, run_id) for row in chunk],
                )
                extracted += len(chunk)

            cursor.execute(f"""
                SELECT COALESCE(SUM(copies), 0), COUNT(*), COUNT_IF(hashes <> 1)
                FROM (
                    SELECT COUNT(*) AS copies, COUNT(DISTINCT RECORD_HASH) AS hashes
                    FROM {stage} GROUP BY SOURCE_SYSTEM, ENTITY, SOURCE_RECORD_ID
                )
            """)
            staged, distinct, conflicts = cursor.fetchone()
            if extracted == 0 or staged != extracted or conflicts:
                raise ValueError("Empty, incomplete or conflicting source deliveries")

            cursor.execute(f"""
                SELECT COUNT(*), COUNT_IF(t.RECORD_HASH <> s.RECORD_HASH)
                FROM ({unique_stage}) AS s JOIN {target} AS t ON {IDENTITY}
            """)
            matched, conflicts = cursor.fetchone()
            if conflicts:
                raise ValueError("Bronze already contains a different image for a source record ID")

            cursor.execute(f"""
                MERGE INTO {target} AS t USING ({unique_stage}) AS s ON {IDENTITY}
                WHEN NOT MATCHED THEN INSERT ({COLUMNS}) VALUES (
                    s.SOURCE_SYSTEM, s.ENTITY, s.SOURCE_RECORD_ID, s.BUSINESS_KEY,
                    s.BATCH_ID, s.SOURCE_OPERATION, TO_TIMESTAMP_TZ(s.SOURCE_EVENT_AT),
                    TO_TIMESTAMP_TZ(s.SOURCE_UPDATED_AT), TO_TIMESTAMP_TZ(s.SOURCE_EFFECTIVE_AT),
                    TO_TIMESTAMP_TZ(s.SOURCE_AVAILABLE_AT), TO_TIMESTAMP_TZ(s.EXTRACTED_AT),
                    s.RUN_ID, s.RECORD_HASH, PARSE_JSON(s.RAW_PAYLOAD)
                )
            """)
            inserted = cursor.fetchone()[0]
            cursor.execute(f"""
                SELECT COUNT(*), COUNT_IF(t.RECORD_HASH <> s.RECORD_HASH)
                FROM ({unique_stage}) AS s JOIN {target} AS t ON {IDENTITY}
            """)
            landed, conflicts = cursor.fetchone()
            if landed != distinct or matched + inserted != distinct or conflicts:
                raise ValueError("Bronze reconciliation failed")
            cursor.execute(f"""
                INSERT INTO {audit} (
                    RUN_ID, SOURCE_SYSTEM, BATCH_ID, ENTITY_SCOPE, EXTRACTED_COUNT,
                    DISTINCT_COUNT, INSERTED_COUNT, MATCHED_COUNT
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (run_id, source, batch, entity or "*", extracted, distinct, inserted, matched))
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
    return LoadResult(run_id, extracted, distinct, inserted, matched)
