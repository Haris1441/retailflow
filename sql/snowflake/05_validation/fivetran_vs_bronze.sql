-- Build-vs-buy reconciliation: Fivetran landing tables vs the Python Bronze landing table.
-- Independent of dbt: both sides are read directly from what each loader wrote.
--
--   Fivetran: RETAIL_DWH.FIVETRAN_BQQ_RETAILFLOW_SOURCE.<TABLE>  (typed columns, one table per source table)
--   Python:   RETAIL_DWH.BRONZE.SOURCE_RECORDS                  (one table, raw JSON in RAW_PAYLOAD)
--
-- Run in Snowsight as ACCOUNTADMIN (it inherits FIVETRAN_ROLE through SYSADMIN) after the
-- Fivetran initial sync succeeds. If your Fivetran connection has another name, replace
-- FIVETRAN_BQQ_RETAILFLOW_SOURCE throughout.
--
-- Fivetran copies the CURRENT BigQuery baseline tables. Bronze also holds change batches
-- BATCH_002..008, so the Bronze side is filtered to BATCH_001.
-- Rows match one to one on the fixture's physical identity, SOURCE_RECORD_ID.

USE DATABASE RETAIL_DWH;

-- 1. Row reconciliation per entity
-- Expect fivetran_rows = bronze_rows = matched, and 0 in both "only_in" columns.
-- Baseline counts: customers 5,000; orders 20,000; order_items 50,000; payments 20,800.
WITH bronze AS (
    SELECT entity, source_record_id
    FROM BRONZE.SOURCE_RECORDS
    WHERE source_system = 'BIGQUERY'
      AND batch_id = 'BATCH_001'
      AND entity IN ('customers', 'orders', 'order_items', 'payments')
),
fivetran AS (
    SELECT 'customers' AS entity, source_record_id FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.CUSTOMERS
    UNION ALL SELECT 'orders', source_record_id FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDERS
    UNION ALL SELECT 'order_items', source_record_id FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDER_ITEMS
    UNION ALL SELECT 'payments', source_record_id FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.PAYMENTS
)
SELECT COALESCE(f.entity, b.entity)                                       AS entity,
       COUNT(f.source_record_id)                                          AS fivetran_rows,
       COUNT(b.source_record_id)                                          AS bronze_rows,
       COUNT_IF(f.source_record_id IS NOT NULL AND b.source_record_id IS NOT NULL) AS matched,
       COUNT_IF(b.source_record_id IS NULL)                               AS only_in_fivetran,
       COUNT_IF(f.source_record_id IS NULL)                               AS only_in_bronze
FROM fivetran f
FULL OUTER JOIN bronze b
  ON f.entity = b.entity AND f.source_record_id = b.source_record_id
GROUP BY 1
ORDER BY 1;

-- 2. Money totals. Expect difference = 0 on every row.
-- Bronze amounts are parsed from the JSON payload the same way Phase 7 staging does.
WITH totals AS (
    SELECT 'orders.order_total' AS measure,
           (SELECT SUM(order_total) FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDERS) AS fivetran_total,
           (SELECT SUM(TRY_TO_DECIMAL(raw_payload:order_total::string, 18, 4))
              FROM BRONZE.SOURCE_RECORDS
             WHERE source_system = 'BIGQUERY' AND batch_id = 'BATCH_001' AND entity = 'orders') AS bronze_total
    UNION ALL
    SELECT 'order_items.line_total',
           (SELECT SUM(line_total) FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDER_ITEMS),
           (SELECT SUM(TRY_TO_DECIMAL(raw_payload:line_total::string, 18, 4))
              FROM BRONZE.SOURCE_RECORDS
             WHERE source_system = 'BIGQUERY' AND batch_id = 'BATCH_001' AND entity = 'order_items')
    UNION ALL
    SELECT 'payments.payment_amount',
           (SELECT SUM(payment_amount) FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.PAYMENTS),
           (SELECT SUM(TRY_TO_DECIMAL(raw_payload:payment_amount::string, 18, 4))
              FROM BRONZE.SOURCE_RECORDS
             WHERE source_system = 'BIGQUERY' AND batch_id = 'BATCH_001' AND entity = 'payments')
)
SELECT measure, fivetran_total, bronze_total, fivetran_total - bronze_total AS difference
FROM totals;

-- 3. Field-level differences on matched order rows. Expect zero rows.
-- A row here means the two loaders disagree on a value (type mapping, decimal scale, time zone).
SELECT f.source_record_id,
       f.order_total  AS fivetran_order_total,
       TRY_TO_DECIMAL(b.raw_payload:order_total::string, 18, 4) AS bronze_order_total,
       f.order_status AS fivetran_order_status,
       b.raw_payload:order_status::string AS bronze_order_status,
       f.order_date   AS fivetran_order_date,
       TRY_TO_TIMESTAMP_TZ(b.raw_payload:order_date::string) AS bronze_order_date
FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDERS f
JOIN BRONZE.SOURCE_RECORDS b
  ON b.source_record_id = f.source_record_id
 AND b.source_system = 'BIGQUERY' AND b.batch_id = 'BATCH_001' AND b.entity = 'orders'
WHERE f.order_total IS DISTINCT FROM TRY_TO_DECIMAL(b.raw_payload:order_total::string, 18, 4)
   OR f.order_status IS DISTINCT FROM b.raw_payload:order_status::string
   OR f.order_date IS DISTINCT FROM TRY_TO_TIMESTAMP_TZ(b.raw_payload:order_date::string)
LIMIT 50;

-- 4. What each loader records about the load itself. Use in the build-vs-buy notes.
SELECT 'fivetran' AS loader, MIN(_fivetran_synced) AS first_loaded_at, MAX(_fivetran_synced) AS last_loaded_at
FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDERS
UNION ALL
SELECT 'python', MIN(ingested_at), MAX(ingested_at)
FROM BRONZE.SOURCE_RECORDS
WHERE source_system = 'BIGQUERY' AND batch_id = 'BATCH_001' AND entity = 'orders';

-- 5. Landing shape. Compare columns: Fivetran adds its own metadata columns,
-- Python keeps provenance (batch, run, hash, availability time) beside the raw JSON.
SELECT table_name, column_name, data_type
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'FIVETRAN_BQQ_RETAILFLOW_SOURCE' AND table_name = 'ORDERS'
ORDER BY ordinal_position;

-- Optional: Fivetran soft deletes. Fivetran marks rows removed at the source with
-- _FIVETRAN_DELETED = TRUE instead of removing them. Uncomment if step 5 lists that column.
-- SELECT COUNT_IF(_fivetran_deleted) AS soft_deleted_orders
-- FROM FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDERS;
