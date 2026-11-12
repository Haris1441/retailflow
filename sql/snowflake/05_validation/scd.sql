-- Phase 11 SCD validation. Run in Snowsight after
--   dbt build --select tag:staging tag:silver tag:data_quality
-- Fixture base date is 2025-01-01, so "day N" below is 2025-01-01 + N days.

USE DATABASE RETAIL_DWH;

-- 1. Row counts. Expected:
--    customers_scd2  BIGQUERY rows 5,020 · keys 5,001 · current 5,001 · keys with history 19
--                    MOCK_API rows 8 · keys 8 · current 8 · keys with history 0
--    products_scd2   rows 1,011 · keys 1,001 · current 1,001 · keys with history 10
SELECT 'customers_scd2' AS history_table, source_system,
       COUNT(*) AS history_rows,
       COUNT(DISTINCT customer_key) AS entity_keys,
       COUNT_IF(is_current) AS current_rows,
       COUNT(DISTINCT IFF(version_number > 1, customer_key, NULL)) AS keys_with_history
FROM SILVER.SILVER_CUSTOMERS_SCD2
GROUP BY 1, 2
UNION ALL
SELECT 'products_scd2', 'BIGQUERY', COUNT(*), COUNT(DISTINCT product_id), COUNT_IF(is_current),
       COUNT(DISTINCT IFF(version_number > 1, product_id, NULL))
FROM SILVER.SILVER_PRODUCTS_SCD2
ORDER BY 1, 2;

-- 2. Which changes created history. Expected 19 customers, each with exactly 2 rows:
--    2-11  loyalty tier and address changed on 2025-02-17 (BATCH_003)
--    12    loyalty STANDARD -> GOLD on 2025-01-13, delivered late in BATCH_006 (arrived 2025-02-24)
--    21    email blanked on 2025-02-21 (BATCH_005 warning, accepted)
--    22    email changed to customer 2's address on 2025-02-21 (BATCH_005 warning, accepted)
--    102, 104, 106, 108, 110  preferred language 'en' on 2025-02-25 (BATCH_007)
--    111   soft delete (status INACTIVE, is_deleted) on 2025-02-27 (BATCH_008)
--    Customers 101, 103, 105, 107, 109 changed only their addresses array, which is not
--    tracked, so they have no new row.
SELECT customer_key, version_number, valid_from, valid_to, is_current,
       loyalty_tier, email_normalized, preferred_language, customer_status, is_deleted, address,
       source_batch_id, source_available_at
FROM SILVER.SILVER_CUSTOMERS_SCD2
WHERE customer_key IN (SELECT customer_key FROM SILVER.SILVER_CUSTOMERS_SCD2 WHERE version_number > 1)
ORDER BY TRY_TO_NUMBER(customer_id), version_number;

-- 3. Late-arriving dimension change. Expected for BIGQUERY:12:
--    version 1 STANDARD 2025-01-01 -> 2025-01-13, version 2 GOLD 2025-01-13 -> open,
--    and version 2 arrived 2025-02-24, 42 days after it took effect.
SELECT version_number, loyalty_tier, valid_from, valid_to, source_batch_id, source_available_at,
       DATEDIFF('day', valid_from, source_available_at) AS days_late
FROM SILVER.SILVER_CUSTOMERS_SCD2
WHERE customer_key = 'BIGQUERY:12'
ORDER BY version_number;

-- 4. Products. Expected: products 2-11 have 2 rows (price +5 and new category on 2025-02-17);
--    products 31-45 have exactly 1 row each, because their BATCH_005 changes were rejected.
SELECT CASE WHEN product_id BETWEEN 2 AND 11 THEN '2-11 updated'
            WHEN product_id BETWEEN 31 AND 45 THEN '31-45 rejected changes'
            ELSE 'other' END AS product_group,
       COUNT(DISTINCT product_id) AS products,
       COUNT(*) AS history_rows,
       MAX(version_number) AS max_versions
FROM SILVER.SILVER_PRODUCTS_SCD2
WHERE product_id BETWEEN 2 AND 11 OR product_id BETWEEN 31 AND 45
GROUP BY 1
ORDER BY 1;
-- Expected: '2-11 updated' 10 products, 20 rows, max 2 · '31-45 rejected changes' 15 products, 15 rows, max 1

-- 5. SCD Type 3. Expected 5,009 rows; 11 with a tier change (customers 2-12).
--    Customer 2: GOLD -> SILVER since 2025-02-17. Customer 12: STANDARD -> GOLD since 2025-01-13.
SELECT COUNT(*) AS customers,
       COUNT_IF(has_tier_change) AS customers_with_tier_change
FROM SILVER.SILVER_CUSTOMER_LOYALTY_SCD3;

SELECT customer_key, previous_loyalty_tier, current_loyalty_tier, loyalty_tier_since
FROM SILVER.SILVER_CUSTOMER_LOYALTY_SCD3
WHERE has_tier_change
ORDER BY TRY_TO_NUMBER(customer_id);

-- 6. Type 1 vs Type 2 in one picture: point-in-time loyalty for orders of customers 2-12.
--    tier_at_order comes from the history row valid on the order date (the first row also covers
--    orders placed before it); current_tier is what a Type 1 dimension would show for every order.
--    Orders placed before a tier change show a different tier. Counts depend on the fixture orders;
--    the point is that rows with tier_matches_current = FALSE exist.
SELECT o.customer_key,
       h.loyalty_tier AS tier_at_order,
       c.loyalty_tier AS current_tier,
       h.loyalty_tier = c.loyalty_tier AS tier_matches_current,
       COUNT(*) AS orders,
       MIN(o.order_at) AS first_order_at,
       MAX(o.order_at) AS last_order_at
FROM SILVER.SILVER_ORDERS AS o
JOIN SILVER.SILVER_CUSTOMERS_SCD2 AS h
  ON h.customer_key = o.customer_key
 AND (o.order_at >= h.valid_from OR h.version_number = 1)
 AND (o.order_at < h.valid_to OR h.valid_to IS NULL)
JOIN SILVER.SILVER_CUSTOMERS AS c
  ON c.customer_key = o.customer_key
WHERE o.source_system = 'BIGQUERY'
  AND TRY_TO_NUMBER(o.customer_id) BETWEEN 2 AND 12
GROUP BY 1, 2, 3, 4
ORDER BY o.customer_key, first_order_at;
