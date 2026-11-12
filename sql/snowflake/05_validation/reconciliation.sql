-- Phase 13 end-to-end reconciliation. Run in Snowsight after
--   dbt build --select tag:staging tag:silver tag:data_quality tag:gold tag:reconciliation
-- The dbt test assert_reconciliation_passes already fails the build if any check fails;
-- these queries show the evidence.

USE DATABASE RETAIL_DWH;

-- 1. Summary. Expected: 6 rows, all PASS, items_failed 0.
--    items_checked: 1) 48 source/entity/batch rows · 2) one row per load run · 3) 48 rows
--                   4) 7 entities · 5) one row per measure and currency · 6) 9 mart measures
SELECT step, layer, check_name, items_checked, items_failed, status, detail_model
FROM DATA_QUALITY.RECON_SUMMARY
ORDER BY step;

-- 2. Source -> Bronze -> Silver per batch. Expected: every row PASS. Totals:
--    BigQuery 119,937 (BATCH_001) + 7,678 (BATCH_002-008) + MOCK_API 40 = 127,655 Bronze rows,
--    each with exactly one disposition.
SELECT s.source_system, s.batch_id,
       SUM(s.source_rows) AS source_rows,
       SUM(s.bronze_rows) AS bronze_rows,
       SUM(d.disposition_rows) AS dispositions,
       SUM(d.accepted) AS accepted, SUM(d.superseded) AS superseded, SUM(d.duplicate) AS duplicate,
       SUM(d.rejected) AS rejected, SUM(d.deleted) AS deleted,
       MIN(s.status) AS source_status, MIN(d.status) AS silver_status
FROM DATA_QUALITY.RECON_SOURCE_TO_BRONZE AS s
JOIN DATA_QUALITY.RECON_BRONZE_TO_SILVER AS d
  ON d.source_system = s.source_system AND d.entity = s.entity AND d.batch_id = s.batch_id
GROUP BY ROLLUP (1, 2)
ORDER BY 1, 2;

-- 3. Load audit. Expected: all PASS. Replay runs (is_replay TRUE) inserted 0 rows, for example the
--    Phase 5 API replay (40 matched) and the Phase 6 incremental runs. Sum of inserted_count = 127,655.
SELECT source_system, batch_id, COUNT(*) AS runs, COUNT_IF(is_replay) AS replay_runs,
       SUM(inserted_count) AS inserted, SUM(matched_count) AS matched, SUM(bronze_rows) AS bronze_rows,
       COUNT_IF(status = 'FAIL') AS failed_runs
FROM DATA_QUALITY.RECON_BRONZE_LOAD_AUDIT
GROUP BY ROLLUP (1, 2)
ORDER BY 1, 2;

-- 4. Silver -> Gold record flow. Expected (silver = gold + excluded):
--    orders 22,106 = 22,105 + 1 (order 20 HELD) · order_lines 52,115 = 52,110 + 5
--    payments 22,909 = 22,906 + 3 · returns 501 = 501 + 0 · inventory 8,408 = 8,408 + 0
--    customers 5,009 = 5,009 + 0 · products 1,001 = 1,001 + 0
SELECT entity, gold_object, silver_rows, gold_rows, excluded_rows, difference, status
FROM DATA_QUALITY.RECON_SILVER_TO_GOLD
ORDER BY entity;

-- 5. Exclusion register. Expected 9 rows:
--    orders       BIGQUERY:20  HELD          1 order line(s) rejected
--    order_lines  BIGQUERY:28, :29 (order 10) and :88, :89 (order 30) QUARANTINED, :59 (order 20) HELD
--    payments     the single payment of each of orders 10, 20 and 30
SELECT entity, record_key, order_key, publication_status, exclusion_reason
FROM DATA_QUALITY.RECON_GOLD_EXCLUSIONS
ORDER BY entity, order_key, record_key;

-- 6. Money, Silver -> Gold per currency. Expected: every row PASS (difference 0). Excluded amounts:
--    LINE_MERCHANDISE  GBP 228.80 (line 59) · UNRESOLVED BIGQUERY:10 2,543.31 · UNRESOLVED BIGQUERY:30 159,320.00
--                      (orders 10 and 30 have quarantined headers, so their currency is not trusted)
--    ORDER_DISCOUNT    GBP 2.00 (order 20)
--    PAYMENTS CHARGE   AED 2,668.48 (order 10) · GBP 259.04 (order 20, pending) · PKR 167,295.00 (order 30)
--    RETURN_CREDITS    0 excluded
SELECT measure, currency, silver_amount, gold_amount, excluded_amount, difference, status
FROM DATA_QUALITY.RECON_FINANCIAL
ORDER BY measure, currency;

-- 7. Gold -> marts. Expected: every row PASS, difference within 0.01.
--    Fact totals: recognized merchandise USD 9,669,882.83 · completed credits USD 53,159.36
SELECT mart_measure, ROUND(fact_value, 2) AS fact_value, ROUND(mart_value, 2) AS mart_value,
       ROUND(difference, 4) AS difference, status
FROM DATA_QUALITY.RECON_GOLD_TO_MARTS
ORDER BY mart_measure;
