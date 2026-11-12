-- Phase 14 validation: file landing -> Bronze -> Silver -> reconciliation and monitoring.
-- Run after the demo in docs/phase-14.md (delivery, redeliver, bad-name, bad-count, resend, dbt build).
-- File batches have IDs like BATCH_20250301T090000, so the filter below finds every file batch.
USE DATABASE RETAIL_DWH;
SET file_batch = 'BATCH_[0-9]{8}T[0-9]{6}';

-- 1. Config: 15 enabled feeds, one regex each.
SELECT COUNT(*) AS feeds, COUNT_IF(IS_ENABLED) AS enabled FROM CONTROL.FILE_CONFIG;
-- Expect 15 | 15

-- 2. Every attempt, oldest first.
SELECT DETECTED_AT, FILE_NAME, STATUS, BATCH_ID, EXPECTED_ROWS, EXTRACTED_ROWS, INSERTED_ROWS,
       MATCHED_ROWS, ERROR_MESSAGE
FROM CONTROL.FILE_REGISTRY ORDER BY DETECTED_AT;
-- Expect, in order:
--   3 x LOADED   delivery: customers 3 rows, products 2, customer_events 5 (all inserted)
--   1 x SKIPPED  per redeliver run: "Identical content already loaded as ..." (the simulator resends the
--                most recently archived file, for example the products file)
--   1 x REJECTED customers_latest_FINAL.jsonl, "File name matches no enabled feed pattern"
--   1 x FAILED   bad-count customers file, "Control file promises 4 rows, the file has 3"
--   1 x LOADED   the same file name after resend, 3 rows inserted

-- 3. Status summary.
SELECT STATUS, COUNT(*) AS attempts, SUM(INSERTED_ROWS) AS inserted
FROM CONTROL.FILE_REGISTRY GROUP BY STATUS ORDER BY STATUS;
-- Expect FAILED 1 | LOADED 4 (13 inserted) | REJECTED 1 | SKIPPED = number of redeliver runs (0 inserted)

-- 4. Lineage: file -> audited run -> Bronze rows. Every row must say OK.
SELECT r.FILE_NAME, r.RUN_ID, a.INSERTED_COUNT, COUNT(b.SOURCE_RECORD_ID) AS bronze_rows,
       IFF(a.RUN_ID IS NOT NULL AND a.INSERTED_COUNT = r.INSERTED_ROWS
           AND COUNT(b.SOURCE_RECORD_ID) = r.INSERTED_ROWS, 'OK', 'CHECK') AS lineage
FROM CONTROL.FILE_REGISTRY AS r
LEFT JOIN AUDIT.BRONZE_LOAD_RUNS AS a ON a.RUN_ID = r.RUN_ID
LEFT JOIN BRONZE.SOURCE_RECORDS AS b ON b.RUN_ID = r.RUN_ID
WHERE r.STATUS = 'LOADED'
GROUP BY r.FILE_NAME, r.RUN_ID, a.RUN_ID, a.INSERTED_COUNT, r.INSERTED_ROWS
ORDER BY r.FILE_NAME;

-- 5. Bronze rows from file batches.
SELECT BATCH_ID, ENTITY, SOURCE_OPERATION, COUNT(*) AS rows_in_bronze
FROM BRONZE.SOURCE_RECORDS
WHERE SOURCE_SYSTEM = 'BIGQUERY' AND RLIKE(BATCH_ID, $file_batch)
GROUP BY 1, 2, 3 ORDER BY 1, 2;
-- Expect first batch: customer_events INSERT 5, customers UPDATE 3, products UPDATE 2;
--        second batch (bad-count, then resent): customers UPDATE 3

-- 6. Silver picked up the file changes: they are the current version of each key.
SELECT 'customers' AS entity, COUNT(*) AS current_from_files FROM SILVER.SILVER_CUSTOMERS WHERE RLIKE(SOURCE_BATCH_ID, $file_batch)
UNION ALL SELECT 'products', COUNT(*) FROM SILVER.SILVER_PRODUCTS WHERE RLIKE(SOURCE_BATCH_ID, $file_batch)
UNION ALL SELECT 'customer_events', COUNT(*) FROM SILVER.SILVER_CUSTOMER_EVENTS WHERE RLIKE(SOURCE_BATCH_ID, $file_batch);
-- Expect customers 6 | products 2 | customer_events 5

-- 7. Late-arriving events: business time weeks before arrival, still loaded by incremental Silver.
SELECT EVENT_KEY, EVENT_AT, LAST_DELIVERY_AVAILABLE_AT,
       DATEDIFF(day, EVENT_AT, LAST_DELIVERY_AVAILABLE_AT) AS days_late
FROM SILVER.SILVER_CUSTOMER_EVENTS
WHERE RLIKE(SOURCE_BATCH_ID, $file_batch) ORDER BY EVENT_KEY;
-- Expect 5 rows; the first two are 21 days late, the others under a day

-- 8. History: each changed customer now has two Type 2 rows and a Type 3 previous tier.
SELECT s.CUSTOMER_KEY, s.VERSION_NUMBER, s.LOYALTY_TIER, s.VALID_FROM, s.VALID_TO, s.IS_CURRENT
FROM SILVER.SILVER_CUSTOMERS_SCD2 AS s
WHERE s.CUSTOMER_KEY IN (SELECT CUSTOMER_KEY FROM SILVER.SILVER_CUSTOMERS WHERE RLIKE(SOURCE_BATCH_ID, $file_batch))
ORDER BY s.CUSTOMER_KEY, s.VERSION_NUMBER;
-- Expect 12 rows (6 customers x 2); version 2 is current and starts at the delivery time

SELECT CUSTOMER_KEY, PREVIOUS_LOYALTY_TIER, CURRENT_LOYALTY_TIER, LOYALTY_TIER_SINCE
FROM SILVER.SILVER_CUSTOMER_LOYALTY_SCD3
WHERE CUSTOMER_KEY IN (SELECT CUSTOMER_KEY FROM SILVER.SILVER_CUSTOMERS WHERE RLIKE(SOURCE_BATCH_ID, $file_batch))
ORDER BY CUSTOMER_KEY;
-- Expect 6 rows: STANDARD -> SILVER, SILVER -> GOLD or GOLD -> SILVER

-- 9. Reconciliation: 7 checks, all PASS. Step 0 covers the 4 loaded files.
SELECT STEP, LAYER, ITEMS_CHECKED, ITEMS_FAILED, STATUS FROM DATA_QUALITY.RECON_SUMMARY ORDER BY STEP;
SELECT FILE_NAME, EXPECTED_ROWS, EXTRACTED_ROWS, AUDIT_EXTRACTED_COUNT, INSERTED_ROWS, AUDIT_INSERTED_COUNT, STATUS
FROM DATA_QUALITY.RECON_LANDING_TO_BRONZE ORDER BY FILE_NAME;
SELECT ENTITY, BATCH_ID, SOURCE_ROWS, BRONZE_ROWS, STATUS
FROM DATA_QUALITY.RECON_SOURCE_TO_BRONZE WHERE RLIKE(BATCH_ID, $file_batch) ORDER BY 2, 1;
-- Expect source_rows = bronze_rows for the 4 file batch rows, with no manifest edit

-- 10. Monitoring.
SELECT FEED_NAME, FILES_LOADED, FILES_SKIPPED, FAILED_ATTEMPTS, OPEN_FAILURES, ROWS_INSERTED,
       LAST_LOADED_BATCH, ROUND(HOURS_SINCE_LAST_LOAD, 2) AS hours_since, FRESHNESS_STATUS, HEALTH
FROM DATA_QUALITY.MON_FILE_FEEDS WHERE FILES_LOADED > 0 OR FAILED_ATTEMPTS > 0 ORDER BY FEED_NAME;
-- Expect customers 2 loaded, 1 failed attempt, 0 open failures, 6 rows;
--        products 1 loaded, 2 rows; customer_events 1 loaded, 5 rows; the redelivered feed also shows
--        its skipped attempts.
--        All ON_TIME and OK.
SELECT ISSUE_TYPE, FILE_NAME, ERROR_MESSAGE FROM DATA_QUALITY.MON_OPEN_FILE_ISSUES;
-- Expect 1 row: REJECTED_NAME customers_latest_FINAL.jsonl (the resent FAILED file is resolved)
