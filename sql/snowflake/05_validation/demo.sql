-- Phase 16 · Live demo evidence. One delivery, followed from the client's file to the KPI layer.
-- Run in Snowsight after `python -m landing scan` and the dbt Cloud `prod_build` run (docs/phase-16.md).
-- Set the batch printed by `python -m landing simulate`, for example BATCH_20250304T090000.
USE DATABASE RETAIL_DWH;
USE WAREHOUSE RETAILFLOW_WH;
SET demo_batch = 'BATCH_20250304T090000';

-- 1. The files: what arrived, what the pipeline decided, and the proof it used.
SELECT DETECTED_AT, FILE_NAME, STATUS, FEED_NAME, EXPECTED_ROWS, EXTRACTED_ROWS, INSERTED_ROWS,
       LEFT(FILE_SHA256, 12) AS sha256_prefix, ERROR_MESSAGE
FROM CONTROL.FILE_REGISTRY
WHERE BATCH_ID = $demo_batch OR BATCH_ID IS NULL AND DETECTED_AT >= DATEADD(hour, -6, CURRENT_TIMESTAMP())
ORDER BY DETECTED_AT;
-- Expect 3 x LOADED: customers 3, products 2, customer_events 5. Plus whatever the failure act added:
-- REJECTED for the hand-named file, SKIPPED for the redelivery.

-- 2. Lineage: file -> audited Bronze run -> Bronze rows. Every row says OK.
SELECT r.FILE_NAME, r.RUN_ID, a.INSERTED_COUNT, COUNT(b.SOURCE_RECORD_ID) AS bronze_rows,
       IFF(a.INSERTED_COUNT = r.INSERTED_ROWS AND COUNT(b.SOURCE_RECORD_ID) = r.INSERTED_ROWS, 'OK', 'CHECK') AS lineage
FROM CONTROL.FILE_REGISTRY AS r
JOIN AUDIT.BRONZE_LOAD_RUNS AS a ON a.RUN_ID = r.RUN_ID
LEFT JOIN BRONZE.SOURCE_RECORDS AS b ON b.RUN_ID = r.RUN_ID
WHERE r.BATCH_ID = $demo_batch AND r.STATUS = 'LOADED'
GROUP BY r.FILE_NAME, r.RUN_ID, a.INSERTED_COUNT, r.INSERTED_ROWS
ORDER BY r.FILE_NAME;

-- 3. Silver: the changes are now the current version of each key.
SELECT 'customers' AS entity, COUNT(*) AS current_rows FROM SILVER.SILVER_CUSTOMERS WHERE SOURCE_BATCH_ID = $demo_batch
UNION ALL SELECT 'products', COUNT(*) FROM SILVER.SILVER_PRODUCTS WHERE SOURCE_BATCH_ID = $demo_batch
UNION ALL SELECT 'customer_events', COUNT(*) FROM SILVER.SILVER_CUSTOMER_EVENTS WHERE SOURCE_BATCH_ID = $demo_batch;
-- Expect 3 | 2 | 5

-- 4. Late arrivals: two events happened 21 days before they arrived and were still picked up
--    by the incremental model (its watermark is arrival time, not business time).
SELECT EVENT_KEY, EVENT_AT, LAST_DELIVERY_AVAILABLE_AT,
       DATEDIFF(day, EVENT_AT, LAST_DELIVERY_AVAILABLE_AT) AS days_late
FROM SILVER.SILVER_CUSTOMER_EVENTS WHERE SOURCE_BATCH_ID = $demo_batch ORDER BY EVENT_KEY;

-- 5. History: each changed customer gets a new Type 2 version starting at the delivery time,
--    and the old version is closed, not overwritten.
SELECT CUSTOMER_KEY, VERSION_NUMBER, LOYALTY_TIER, VALID_FROM, VALID_TO, IS_CURRENT
FROM SILVER.SILVER_CUSTOMERS_SCD2
WHERE CUSTOMER_KEY IN (SELECT CUSTOMER_KEY FROM SILVER.SILVER_CUSTOMERS WHERE SOURCE_BATCH_ID = $demo_batch)
ORDER BY CUSTOMER_KEY, VERSION_NUMBER;

SELECT PRODUCT_ID, VERSION_NUMBER, BASE_PRICE, VALID_FROM, VALID_TO, IS_CURRENT
FROM SILVER.SILVER_PRODUCTS_SCD2
WHERE PRODUCT_ID IN (SELECT PRODUCT_ID FROM SILVER.SILVER_PRODUCTS WHERE SOURCE_BATCH_ID = $demo_batch)
ORDER BY PRODUCT_ID, VERSION_NUMBER;
-- Expect the new price = old price + 5 on the current row

-- 6. Gold: point-in-time. Past orders keep the tier and price in force when they were placed;
--    the dimension's current row shows today's values.
SELECT d.CUSTOMER_KEY, COUNT(*) AS order_lines,
       LISTAGG(DISTINCT d.LOYALTY_TIER, ', ') AS tier_at_order_time,
       MAX(c.LOYALTY_TIER) AS tier_now
FROM GOLD.FCT_SALES AS f
JOIN GOLD.DIM_CUSTOMER AS d ON d.CUSTOMER_SK = f.CUSTOMER_SK
JOIN GOLD.DIM_CUSTOMER AS c ON c.CUSTOMER_KEY = d.CUSTOMER_KEY AND c.IS_CURRENT
WHERE d.CUSTOMER_KEY IN (SELECT CUSTOMER_KEY FROM SILVER.SILVER_CUSTOMERS WHERE SOURCE_BATCH_ID = $demo_batch)
GROUP BY d.CUSTOMER_KEY ORDER BY d.CUSTOMER_KEY;
-- A customer with no orders returns no row; that is expected

-- 7. Reconciliation gate: every check PASS, and step 0 now includes the demo files.
SELECT STEP, LAYER, ITEMS_CHECKED, ITEMS_FAILED, STATUS FROM DATA_QUALITY.RECON_SUMMARY ORDER BY STEP;
SELECT FILE_NAME, EXPECTED_ROWS, EXTRACTED_ROWS, INSERTED_ROWS, AUDIT_INSERTED_COUNT, STATUS
FROM DATA_QUALITY.RECON_LANDING_TO_BRONZE WHERE FILE_NAME ILIKE '%' || REPLACE($demo_batch, 'BATCH_', '') || '%'
ORDER BY FILE_NAME;

-- 8. Monitoring: what an operator looks at every morning.
SELECT FEED_NAME, FILES_LOADED, FILES_SKIPPED, FAILED_ATTEMPTS, OPEN_FAILURES, ROWS_INSERTED,
       LAST_LOADED_BATCH, LAST_ATTEMPT_STATUS, FRESHNESS_STATUS, HEALTH
FROM DATA_QUALITY.MON_FILE_FEEDS WHERE FILES_LOADED > 0 OR FAILED_ATTEMPTS > 0 ORDER BY FEED_NAME;
SELECT ISSUE_TYPE, FILE_NAME, ERROR_MESSAGE FROM DATA_QUALITY.MON_OPEN_FILE_ISSUES;
-- Expect only the deliberately misnamed file(s) as open issues
