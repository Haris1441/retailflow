-- Phase 14 · File-based ingestion control tables. Run once in Snowsight as ACCOUNTADMIN.
--
-- FILE_CONFIG says which file names belong to which feed. Each pattern is a Python regular
-- expression matched against the whole file name. It must capture the group batch_ts
-- (YYYYMMDDTHHMMSS), which becomes the batch ID BATCH_<batch_ts>. Adding a feed means adding a
-- row here, not changing code.
--
-- FILE_REGISTRY has one row per processing attempt of one file: what arrived, what the control
-- file promised, what was loaded, and the final status.
--   RECEIVED  attempt started (a row stuck here means the process stopped mid-file)
--   LOADED    validated and merged into Bronze; RUN_ID links to AUDIT.BRONZE_LOAD_RUNS
--   SKIPPED   identical content (same SHA-256) was already LOADED; nothing was loaded again
--   FAILED    validation or load failed; nothing was loaded (the Bronze load is one transaction)
--   REJECTED  the file name matches no enabled feed
USE ROLE ACCOUNTADMIN;
USE DATABASE RETAIL_DWH;

CREATE TABLE IF NOT EXISTS CONTROL.FILE_CONFIG (
    FEED_NAME VARCHAR NOT NULL,
    SOURCE_SYSTEM VARCHAR NOT NULL,
    ENTITY VARCHAR NOT NULL,
    FILE_PATTERN VARCHAR NOT NULL,
    FILE_FORMAT VARCHAR NOT NULL DEFAULT 'JSONL',
    REQUIRES_CONTROL_FILE BOOLEAN NOT NULL DEFAULT TRUE,
    EXPECTED_EVERY_HOURS NUMBER NOT NULL DEFAULT 24,
    IS_ENABLED BOOLEAN NOT NULL DEFAULT TRUE,
    UPDATED_AT TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (FEED_NAME)
);

CREATE TABLE IF NOT EXISTS CONTROL.FILE_REGISTRY (
    ATTEMPT_ID VARCHAR NOT NULL,
    FILE_NAME VARCHAR NOT NULL,
    FILE_SHA256 VARCHAR NOT NULL,
    FILE_SIZE_BYTES NUMBER NOT NULL,
    FEED_NAME VARCHAR,
    SOURCE_SYSTEM VARCHAR,
    ENTITY VARCHAR,
    BATCH_ID VARCHAR,
    EXPECTED_ROWS NUMBER,
    EXTRACTED_ROWS NUMBER,
    INSERTED_ROWS NUMBER,
    MATCHED_ROWS NUMBER,
    RUN_ID VARCHAR,
    STATUS VARCHAR NOT NULL,
    ERROR_MESSAGE VARCHAR,
    DETECTED_AT TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    FINISHED_AT TIMESTAMP_TZ,
    PRIMARY KEY (ATTEMPT_ID)
);

-- One feed per BigQuery entity. The retailer's core system (modelled as SOURCE_SYSTEM BIGQUERY)
-- also sends its change batches as files: retailco_<entity>_<YYYYMMDDTHHMMSS>_<seq>.jsonl,
-- each with a control file of the same name ending in .ctl.
MERGE INTO CONTROL.FILE_CONFIG AS target
USING (
    SELECT 'retailco_' || column1 AS feed_name, 'BIGQUERY' AS source_system, column1 AS entity,
           'retailco_' || column1 || '_(?P<batch_ts>[0-9]{8}T[0-9]{6})_(?P<seq>[0-9]{3})[.]jsonl' AS file_pattern
    FROM VALUES ('categories'), ('brands'), ('suppliers'), ('stores'), ('customers'), ('products'),
                ('promotions'), ('exchange_rates'), ('order_items'), ('orders'),
                ('order_promotions'), ('payments'), ('inventory'), ('returns'), ('customer_events')
) AS source
ON target.FEED_NAME = source.feed_name
WHEN NOT MATCHED THEN INSERT (FEED_NAME, SOURCE_SYSTEM, ENTITY, FILE_PATTERN)
VALUES (source.feed_name, source.source_system, source.entity, source.file_pattern);

-- The loader reads the config and writes the registry.
GRANT SELECT ON TABLE CONTROL.FILE_CONFIG TO ROLE RETAILFLOW_LOADER;
GRANT SELECT, INSERT, UPDATE ON TABLE CONTROL.FILE_REGISTRY TO ROLE RETAILFLOW_LOADER;

-- dbt reads both for reconciliation and monitoring.
GRANT USAGE ON SCHEMA CONTROL TO ROLE RETAIL_DBT_ROLE;
GRANT SELECT ON TABLE CONTROL.FILE_CONFIG TO ROLE RETAIL_DBT_ROLE;
GRANT SELECT ON TABLE CONTROL.FILE_REGISTRY TO ROLE RETAIL_DBT_ROLE;

SELECT FEED_NAME, ENTITY, FILE_PATTERN, IS_ENABLED FROM CONTROL.FILE_CONFIG ORDER BY FEED_NAME;
