-- Phase 9 data quality validation. Run in Snowsight after
--   dbt build --select tag:staging tag:silver tag:data_quality
-- Expected values come from DATA_GENERATION_MANIFEST.md (BATCH_001 defects and BATCH_005).

USE DATABASE RETAIL_DWH;

-- 1. BigQuery dispositions. Expected:
--    ACCEPTED 126,305 · SUPERSEDED 1,048 · DUPLICATE 240 · REJECTED 21 · DELETED 1 · total 127,615
--    vs Phase 8: four keys lost their only version (orders 10 and 30, line 58, return 60002),
--    and 17 earlier trusted versions moved from SUPERSEDED back to ACCEPTED.
SELECT disposition, COUNT(*) AS deliveries
FROM SILVER.SILVER_RECORD_DISPOSITIONS
WHERE source_system = 'BIGQUERY'
GROUP BY 1
ORDER BY 1;

-- 2. REJECT results by rule. Expected (21 in total, all OPEN):
--    PRD_NEGATIVE_PRICE 10 · PRD_MISSING_CATEGORY 5 · CAT_PARENT_CYCLE 1 · INV_NEGATIVE_QUANTITY 1
--    RET_QUANTITY_INVALID 1 · OLI_NONPOSITIVE_QUANTITY 1 · ORD_MISSING_CUSTOMER 1 · ORD_AMOUNT_MISMATCH 1
SELECT rule_id, entity, batch_id, COUNT(*) AS failures, COUNT_IF(is_waived) AS waived
FROM DATA_QUALITY.DQ_RULE_RESULTS
WHERE severity = 'REJECT'
GROUP BY 1, 2, 3
ORDER BY 1, 3;

-- 3. WARN results on current rows. Expected:
--    CUS_MISSING_EMAIL 101 (100 baseline + customer 21 blanked in BATCH_005)
--    CUS_MALFORMED_EMAIL 50 · CUS_SHARED_EMAIL 2 (customers 2 and 22)
--    PRD_MISSING_DESCRIPTION 10 · SUP_MISSING_CONTACT 1 (supplier 20)
SELECT rule_id, COUNT(*) AS warnings
FROM DATA_QUALITY.DQ_RULE_RESULTS
WHERE severity = 'WARN'
GROUP BY 1
ORDER BY 1;

-- 4. Quarantine. Expected 21 OPEN, 0 WAIVED. Review the payloads here.
SELECT quarantine_status, entity, business_key, batch_id, failed_rules, observed_values
FROM DATA_QUALITY.DQ_QUARANTINE
ORDER BY entity, business_key;

-- 5. Order publication. Expected:
--    PUBLISHABLE 22,105 · HELD 1 (order 20, line 58 rejected) · QUARANTINED 2 (orders 10 and 30)
SELECT publication_status, COUNT(*) AS orders, LISTAGG(CASE WHEN publication_status <> 'PUBLISHABLE' THEN order_key END, ', ') AS examples
FROM SILVER.SILVER_ORDER_PUBLICATION
GROUP BY 1
ORDER BY 1;

-- 6. Silver counts that change in Phase 9. Expected:
--    orders 22,106 · order_items 52,115 · returns 501
--    unchanged: products 1,001 · categories 9 · inventory 8,408 (fallback to the last trusted version)
SELECT 'orders' AS silver_table, COUNT(*) AS row_count FROM SILVER.SILVER_ORDERS
UNION ALL SELECT 'order_items', COUNT(*) FROM SILVER.SILVER_ORDER_ITEMS
UNION ALL SELECT 'returns', COUNT(*) FROM SILVER.SILVER_RETURNS
UNION ALL SELECT 'products', COUNT(*) FROM SILVER.SILVER_PRODUCTS
UNION ALL SELECT 'categories', COUNT(*) FROM SILVER.SILVER_CATEGORIES
UNION ALL SELECT 'inventory', COUNT(*) FROM SILVER.SILVER_INVENTORY;

-- 7. The Phase 8 defect list is now empty in current Silver. Expected 0 on every row.
SELECT 'order with missing customer' AS defect, COUNT(*) AS rows_found
FROM SILVER.SILVER_ORDERS o
LEFT JOIN SILVER.SILVER_CUSTOMERS c ON c.customer_key = o.customer_key
WHERE c.customer_key IS NULL
UNION ALL SELECT 'products with negative base price', COUNT(*) FROM SILVER.SILVER_PRODUCTS WHERE base_price < 0
UNION ALL SELECT 'products with missing category', COUNT(*)
FROM SILVER.SILVER_PRODUCTS p LEFT JOIN SILVER.SILVER_CATEGORIES c ON c.category_id = p.category_id
WHERE c.category_id IS NULL
UNION ALL SELECT 'returns over the sold quantity', COUNT(*)
FROM SILVER.SILVER_RETURNS r JOIN SILVER.SILVER_ORDER_ITEMS i ON i.order_item_key = r.order_item_key
WHERE r.return_quantity > i.quantity
UNION ALL SELECT 'negative stock snapshots', COUNT(*) FROM SILVER.SILVER_INVENTORY WHERE quantity_on_hand < 0
UNION ALL SELECT 'order lines with zero quantity', COUNT(*) FROM SILVER.SILVER_ORDER_ITEMS WHERE quantity <= 0
UNION ALL SELECT 'category 1 with a parent (cycle)', COUNT(*) FROM SILVER.SILVER_CATEGORIES
WHERE category_id = 1 AND parent_category_id IS NOT NULL;

-- 8. Fallback to the last trusted version. Expected: 17 rows, none from BATCH_005.
--    Products 31-45, category 1 and the store 1 / product 1 snapshot keep an earlier trusted version.
SELECT 'products' AS entity, product_id::varchar AS business_key, source_batch_id, base_price::varchar AS value
FROM SILVER.SILVER_PRODUCTS WHERE product_id BETWEEN 31 AND 45
UNION ALL
SELECT 'categories', category_id::varchar, source_batch_id, COALESCE(parent_category_id::varchar, 'no parent')
FROM SILVER.SILVER_CATEGORIES WHERE category_id = 1
UNION ALL
SELECT 'inventory', inventory_id, source_batch_id, quantity_on_hand::varchar
FROM SILVER.SILVER_INVENTORY
WHERE source_system = 'BIGQUERY' AND store_id = 1 AND product_id = 1
  AND snapshot_date = (SELECT MIN(snapshot_date) FROM SILVER.SILVER_INVENTORY WHERE store_id = 1 AND product_id = 1)
ORDER BY 1, 2;
