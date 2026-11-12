-- Phase 10 incremental processing, CDC replay and late arrivals. Run in Snowsight.
-- The runbook (docs/phase-10.md) has five dbt builds, A to E. After EACH build, run section 1
-- with that step's label. Run section 0 once before build A.

USE DATABASE RETAIL_DWH;

-- 0. Once, before build A: a small capture table in AUDIT.
CREATE TABLE IF NOT EXISTS AUDIT.PHASE10_CAPTURES (
    step VARCHAR,
    captured_at TIMESTAMP_TZ,
    silver_table VARCHAR,
    source_system VARCHAR,
    row_count NUMBER,
    rows_rewritten NUMBER,
    content_hash NUMBER
);
TRUNCATE TABLE AUDIT.PHASE10_CAPTURES;

-- 1. After each build: change the label to A, B, C, D or E, then run both statements.
--    rows_rewritten = rows the build wrote since the previous capture.
--    content_hash ignores silver_processed_at, so it changes only when the data changes.
SET step = 'A';

INSERT INTO AUDIT.PHASE10_CAPTURES
WITH previous AS (
    SELECT COALESCE(MAX(captured_at), '1900-01-01 00:00:00 +00:00'::TIMESTAMP_TZ) AS ts
    FROM AUDIT.PHASE10_CAPTURES
),
stats AS (
    SELECT 'silver_payments' AS silver_table, source_system, COUNT(*) AS row_count,
           COUNT_IF(silver_processed_at > (SELECT ts FROM previous)) AS rows_rewritten
    FROM SILVER.SILVER_PAYMENTS GROUP BY 1, 2
    UNION ALL
    SELECT 'silver_customer_events', source_system, COUNT(*),
           COUNT_IF(silver_processed_at > (SELECT ts FROM previous))
    FROM SILVER.SILVER_CUSTOMER_EVENTS GROUP BY 1, 2
),
hashes AS (
    SELECT 'silver_payments' AS silver_table, source_system, HASH_AGG(*) AS content_hash
    FROM (SELECT * EXCLUDE (silver_processed_at) FROM SILVER.SILVER_PAYMENTS)
    GROUP BY 1, 2
    UNION ALL
    SELECT 'silver_customer_events', source_system, HASH_AGG(*)
    FROM (SELECT * EXCLUDE (silver_processed_at) FROM SILVER.SILVER_CUSTOMER_EVENTS)
    GROUP BY 1, 2
)
SELECT $step, CURRENT_TIMESTAMP(), s.silver_table, s.source_system, s.row_count, s.rows_rewritten, h.content_hash
FROM stats AS s
JOIN hashes AS h ON h.silver_table = s.silver_table AND h.source_system = s.source_system;

-- 2. All captures. Expected BIGQUERY rows (MOCK_API stays at 8 rows per table):
--    step  table                   row_count  rows_rewritten
--    A     silver_payments            22,800          22,800   full refresh, baseline + BATCH_002
--    A     silver_customer_events     12,000          12,000
--    B     silver_payments            22,801             502   BATCH_003 500 updates, BATCH_004 failed payment + refund
--    B     silver_customer_events     12,000               0   no event changes in BATCH_003-004
--    C     silver_payments            22,901             100   BATCH_006 late-arriving payments
--    C     silver_customer_events     11,999             250   240 duplicates + 10 device changes; event 401 removed
--    D     silver_payments            22,901             100   replay re-reads BATCH_006 (96 h lookback)
--    D     silver_customer_events     11,999              10   replay re-reads BATCH_007
--    E     silver_payments            22,901          22,901   full refresh
--    E     silver_customer_events     11,999          11,999
--    MOCK_API rows are rewritten only in A and E, plus any API deliveries inside D's lookback.
SELECT step, silver_table, source_system, row_count, rows_rewritten, content_hash
FROM AUDIT.PHASE10_CAPTURES
ORDER BY silver_table, source_system, step;

-- 3. Proof. Expected TRUE in both columns for every row:
--    replay_changed_nothing          C (incremental) = D (replay with lookback)
--    incremental_equals_full_refresh C (incremental) = E (full refresh)
SELECT silver_table, source_system,
       MAX(IFF(step = 'C', content_hash, NULL)) = MAX(IFF(step = 'D', content_hash, NULL)) AS replay_changed_nothing,
       MAX(IFF(step = 'C', content_hash, NULL)) = MAX(IFF(step = 'E', content_hash, NULL)) AS incremental_equals_full_refresh
FROM AUDIT.PHASE10_CAPTURES
GROUP BY 1, 2
ORDER BY 1, 2;

-- 4. Late arrivals (run after C or E). Expected: 100 late payments, all 100 older in business
--    time than payments already loaded, so a business-time watermark would have skipped them.
SELECT COUNT(*) AS batch_006_payments,
       COUNT_IF(payment_at < (
           SELECT MAX(payment_at) FROM SILVER.SILVER_PAYMENTS
           WHERE source_system = 'BIGQUERY' AND source_batch_id <= 'BATCH_004'
       )) AS older_than_loaded_business_time,
       MIN(payment_at) AS earliest_payment_at,
       MIN(last_delivery_available_at) AS arrived_at
FROM SILVER.SILVER_PAYMENTS
WHERE source_batch_id = 'BATCH_006';

-- 5. Hard delete reached Silver (after C or E). Expected 0 rows for event 401, 10 events with device_os.
SELECT COUNT_IF(event_key = 'BIGQUERY:401') AS event_401_rows,
       COUNT_IF(source_system = 'BIGQUERY' AND device_os IS NOT NULL) AS events_with_device_os
FROM SILVER.SILVER_CUSTOMER_EVENTS;

-- 6. After E, Phase 9 results are unchanged. Expected:
--    ACCEPTED 126,305 · SUPERSEDED 1,048 · DUPLICATE 240 · REJECTED 21 · DELETED 1
SELECT disposition, COUNT(*) AS deliveries
FROM SILVER.SILVER_RECORD_DISPOSITIONS
WHERE source_system = 'BIGQUERY'
GROUP BY 1
ORDER BY 1;
