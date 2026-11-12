-- Run once in Snowsight after Phase 5. This creates control metadata only.
USE DATABASE RETAIL_DWH;

CREATE TABLE IF NOT EXISTS CONTROL.ENTITY_CONFIG (
    SOURCE_SYSTEM VARCHAR NOT NULL,
    ENTITY VARCHAR NOT NULL,
    LOAD_STRATEGY VARCHAR NOT NULL,
    WATERMARK_FIELD VARCHAR,
    OVERLAP_MINUTES NUMBER NOT NULL DEFAULT 60,
    MAX_BACKFILL_DAYS NUMBER NOT NULL DEFAULT 45,
    IS_ENABLED BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (SOURCE_SYSTEM, ENTITY)
);

CREATE TABLE IF NOT EXISTS CONTROL.WATERMARKS (
    SOURCE_SYSTEM VARCHAR NOT NULL,
    ENTITY VARCHAR NOT NULL,
    LAST_SUCCESSFUL_WATERMARK TIMESTAMP_TZ,
    LAST_SUCCESSFUL_RUN_ID VARCHAR,
    UPDATED_AT TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (SOURCE_SYSTEM, ENTITY)
);

CREATE TABLE IF NOT EXISTS CONTROL.PIPELINE_RUNS (
    RUN_ID VARCHAR NOT NULL,
    PIPELINE_NAME VARCHAR NOT NULL,
    SOURCE_SYSTEM VARCHAR NOT NULL,
    ENTITY_SCOPE VARCHAR NOT NULL,
    LOAD_TYPE VARCHAR NOT NULL,
    STATUS VARCHAR NOT NULL,
    STARTED_AT TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    FINISHED_AT TIMESTAMP_TZ,
    ERROR_MESSAGE VARCHAR,
    PRIMARY KEY (RUN_ID)
);

MERGE INTO CONTROL.ENTITY_CONFIG AS target
USING (
    SELECT column1 AS source_system, column2 AS entity, column3 AS load_strategy,
           column4 AS watermark_field, column5 AS overlap_minutes, column6 AS max_backfill_days
    FROM VALUES
      ('BIGQUERY', 'customers', 'OVERLAP_WATERMARK', 'source_available_at', 60, 45),
      ('BIGQUERY', 'products', 'OVERLAP_WATERMARK', 'source_available_at', 60, 45),
      ('BIGQUERY', 'orders', 'OVERLAP_WATERMARK', 'source_available_at', 60, 45),
      ('BIGQUERY', 'order_items', 'OVERLAP_WATERMARK', 'source_available_at', 60, 45),
      ('BIGQUERY', 'payments', 'OVERLAP_WATERMARK', 'source_available_at', 60, 45),
      ('BIGQUERY', 'customer_events', 'OVERLAP_WATERMARK', 'source_available_at', 60, 45),
      ('MOCK_API', 'customers', 'OVERLAP_WATERMARK', 'updated_at', 60, 45),
      ('MOCK_API', 'orders', 'OVERLAP_WATERMARK', 'updated_at', 60, 45),
      ('MOCK_API', 'payments', 'OVERLAP_WATERMARK', 'updated_at', 60, 45),
      ('MOCK_API', 'events', 'OVERLAP_WATERMARK', 'updated_at', 60, 45),
      ('MOCK_API', 'inventory', 'OVERLAP_WATERMARK', 'updated_at', 60, 45)
) AS source
ON target.source_system = source.source_system AND target.entity = source.entity
WHEN NOT MATCHED THEN INSERT (
    SOURCE_SYSTEM, ENTITY, LOAD_STRATEGY, WATERMARK_FIELD, OVERLAP_MINUTES, MAX_BACKFILL_DAYS
) VALUES (
    source.source_system, source.entity, source.load_strategy, source.watermark_field,
    source.overlap_minutes, source.max_backfill_days
);
