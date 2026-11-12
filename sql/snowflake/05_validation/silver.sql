-- NOTE: Phase 9 changes the expected orders (22,106), order_items (52,115) and returns (501) counts
-- and empties check 6. Use data_quality.sql for the current expectations.
-- Phase 8 Silver validation. Run in Snowsight after
--   dbt build --select tag:staging tag:silver
-- Expected values come from DATA_GENERATION_MANIFEST.md (BATCH_001-008) and the API fixture.

USE DATABASE RETAIL_DWH;

-- 1. Every Bronze delivery has exactly one disposition. Expect zero rows.
WITH bronze AS (
    SELECT source_system, entity, COUNT(*) AS bronze_rows
    FROM BRONZE.SOURCE_RECORDS GROUP BY 1, 2
), silver AS (
    SELECT source_system, entity, COUNT(*) AS disposition_rows
    FROM SILVER.SILVER_RECORD_DISPOSITIONS GROUP BY 1, 2
)
SELECT COALESCE(b.source_system, s.source_system) AS source_system,
       COALESCE(b.entity, s.entity) AS entity, b.bronze_rows, s.disposition_rows
FROM bronze b FULL OUTER JOIN silver s
  ON b.source_system = s.source_system AND b.entity = s.entity
WHERE b.bronze_rows IS DISTINCT FROM s.disposition_rows;


-- 2. BigQuery dispositions. Expected:
--    ACCEPTED 126,309 · SUPERSEDED 1,065 · DUPLICATE 240 · DELETED 1 · total 127,615
--    (119,937 baseline + 7,678 change rows)
SELECT disposition, COUNT(*) AS deliveries
FROM SILVER.SILVER_RECORD_DISPOSITIONS
WHERE source_system = 'BIGQUERY'
GROUP BY 1
ORDER BY 1;

-- 3. Where the duplicates and the delete came from. Expected:
--    customer_events DUPLICATE 240 (all BATCH_005) · customer_events DELETED 1 (BATCH_008, event 401)
SELECT entity, batch_id, disposition, COUNT(*) AS deliveries
FROM SILVER.SILVER_RECORD_DISPOSITIONS
WHERE disposition IN ('DUPLICATE', 'DELETED')
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- 4. Silver row counts. Expected:
--    customers 5,009 (5,001 BigQuery + 8 API) · customer_addresses 20
--    customer_events 12,007 (11,999 + 8) · customer_event_products 12,007
--    products 1,001 · categories 9 · brands 25 · suppliers 20 · stores 12 · promotions 3
--    exchange_rates 236 · orders 22,108 (22,100 + 8) · order_items 52,116 (52,100 + 16)
--    order_item_discounts 8 · order_shipments 8 · order_promotions 2,000
--    payments 22,909 (22,901 + 8) · inventory 8,408 (8,400 + 8) · returns 502
SELECT 'customers' AS silver_table, COUNT(*) AS row_count FROM SILVER.SILVER_CUSTOMERS
UNION ALL SELECT 'customer_addresses', COUNT(*) FROM SILVER.SILVER_CUSTOMER_ADDRESSES
UNION ALL SELECT 'customer_events', COUNT(*) FROM SILVER.SILVER_CUSTOMER_EVENTS
UNION ALL SELECT 'customer_event_products', COUNT(*) FROM SILVER.SILVER_CUSTOMER_EVENT_PRODUCTS
UNION ALL SELECT 'products', COUNT(*) FROM SILVER.SILVER_PRODUCTS
UNION ALL SELECT 'categories', COUNT(*) FROM SILVER.SILVER_CATEGORIES
UNION ALL SELECT 'brands', COUNT(*) FROM SILVER.SILVER_BRANDS
UNION ALL SELECT 'suppliers', COUNT(*) FROM SILVER.SILVER_SUPPLIERS
UNION ALL SELECT 'stores', COUNT(*) FROM SILVER.SILVER_STORES
UNION ALL SELECT 'promotions', COUNT(*) FROM SILVER.SILVER_PROMOTIONS
UNION ALL SELECT 'exchange_rates', COUNT(*) FROM SILVER.SILVER_EXCHANGE_RATES
UNION ALL SELECT 'orders', COUNT(*) FROM SILVER.SILVER_ORDERS
UNION ALL SELECT 'order_items', COUNT(*) FROM SILVER.SILVER_ORDER_ITEMS
UNION ALL SELECT 'order_item_discounts', COUNT(*) FROM SILVER.SILVER_ORDER_ITEM_DISCOUNTS
UNION ALL SELECT 'order_shipments', COUNT(*) FROM SILVER.SILVER_ORDER_SHIPMENTS
UNION ALL SELECT 'order_promotions', COUNT(*) FROM SILVER.SILVER_ORDER_PROMOTIONS
UNION ALL SELECT 'payments', COUNT(*) FROM SILVER.SILVER_PAYMENTS
UNION ALL SELECT 'inventory', COUNT(*) FROM SILVER.SILVER_INVENTORY
UNION ALL SELECT 'returns', COUNT(*) FROM SILVER.SILVER_RETURNS
ORDER BY 1;

-- 5. Spot checks on specific change scenarios. Each row states its expected value.
SELECT 'customer 111 soft-deleted (expect TRUE, INACTIVE)' AS check_name,
       is_deleted::varchar || ', ' || customer_status AS actual
FROM SILVER.SILVER_CUSTOMERS WHERE customer_key = 'BIGQUERY:111'
UNION ALL
SELECT 'event 401 hard-deleted (expect 0 rows)', COUNT(*)::varchar
FROM SILVER.SILVER_CUSTOMER_EVENTS WHERE event_key = 'BIGQUERY:401'
UNION ALL
SELECT 'order 10040 canceled in BATCH_004 (expect CANCELED)', order_status
FROM SILVER.SILVER_ORDERS WHERE order_key = 'BIGQUERY:10040'
UNION ALL
SELECT 'customer 21 blank email normalized (expect NULL)', COALESCE(email_normalized, 'NULL')
FROM SILVER.SILVER_CUSTOMERS WHERE customer_key = 'BIGQUERY:21'
UNION ALL
SELECT 'customers with preferred_language (expect 5)', COUNT(*)::varchar
FROM SILVER.SILVER_CUSTOMERS WHERE preferred_language IS NOT NULL
UNION ALL
SELECT 'events with device_os from BATCH_007 (expect 10)', COUNT(*)::varchar
FROM SILVER.SILVER_CUSTOMER_EVENTS WHERE device_os IS NOT NULL
UNION ALL
SELECT 'API orders mapped to store 2 (expect 8)', COUNT(*)::varchar
FROM SILVER.SILVER_ORDERS WHERE source_system = 'MOCK_API' AND store_id = 2
UNION ALL
SELECT 'rates whose current version is the BATCH_006 correction (expect 1)', COUNT(*)::varchar
FROM SILVER.SILVER_EXCHANGE_RATES WHERE source_batch_id = 'BATCH_006';

-- 6. Known Phase 9 defects that Silver still carries (latest version wins in Phase 8).
--    Expected: order 10 with missing customer, products 31-45, return 60002, inventory negative stock,
--    category 1 with parent 7. These become rejections or quarantine in Phase 9.
SELECT 'order with missing customer' AS defect, COUNT(*) AS rows_found
FROM SILVER.SILVER_ORDERS o
LEFT JOIN SILVER.SILVER_CUSTOMERS c ON c.customer_key = o.customer_key
WHERE c.customer_key IS NULL
UNION ALL SELECT 'products with negative base price', COUNT(*) FROM SILVER.SILVER_PRODUCTS WHERE base_price < 0
UNION ALL SELECT 'products with missing category', COUNT(*)
FROM SILVER.SILVER_PRODUCTS p LEFT JOIN SILVER.SILVER_CATEGORIES c ON c.category_id = p.category_id
WHERE c.category_id IS NULL
UNION ALL SELECT 'returns over 1 unit', COUNT(*) FROM SILVER.SILVER_RETURNS WHERE return_quantity > 1
UNION ALL SELECT 'negative stock snapshots', COUNT(*) FROM SILVER.SILVER_INVENTORY WHERE quantity_on_hand < 0
UNION ALL SELECT 'order lines with zero quantity', COUNT(*) FROM SILVER.SILVER_ORDER_ITEMS WHERE quantity <= 0;
