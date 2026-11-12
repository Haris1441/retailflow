-- Run after BATCH_001. Expected final result is zero rows.
DECLARE fixture_base_date DATE DEFAULT DATE '2025-01-01';
DECLARE batch_timestamp TIMESTAMP DEFAULT TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY));

CREATE TEMP TABLE validation_results AS
SELECT 'categories: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT category_id FROM `retailflow_source.categories` GROUP BY category_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'brands: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT brand_id FROM `retailflow_source.brands` GROUP BY brand_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'suppliers: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT supplier_id FROM `retailflow_source.suppliers` GROUP BY supplier_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'stores: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT store_id FROM `retailflow_source.stores` GROUP BY store_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'customers: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT customer_id FROM `retailflow_source.customers` GROUP BY customer_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'products: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT product_id FROM `retailflow_source.products` GROUP BY product_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'promotions: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT promotion_id FROM `retailflow_source.promotions` GROUP BY promotion_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'exchange_rates: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT rate_date, from_currency, to_currency FROM `retailflow_source.exchange_rates` GROUP BY rate_date, from_currency, to_currency HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'order_items: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT order_item_id FROM `retailflow_source.order_items` GROUP BY order_item_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'orders: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT order_id FROM `retailflow_source.orders` GROUP BY order_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'order_promotions: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT order_promotion_id FROM `retailflow_source.order_promotions` GROUP BY order_promotion_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'payments: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT payment_id FROM `retailflow_source.payments` GROUP BY payment_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'inventory: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT store_id, product_id, snapshot_date FROM `retailflow_source.inventory` GROUP BY store_id, product_id, snapshot_date HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'returns: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT return_id FROM `retailflow_source.returns` GROUP BY return_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'customer_events: duplicate business keys' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM (SELECT event_id FROM `retailflow_source.customer_events` GROUP BY event_id HAVING COUNT(*) > 1)) AS actual
UNION ALL
SELECT 'categories: rows' AS check_name, 9 AS expected, (SELECT COUNT(*) FROM `retailflow_source.categories`) AS actual
UNION ALL
SELECT 'categories: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.categories`) AS actual
UNION ALL
SELECT 'brands: rows' AS check_name, 25 AS expected, (SELECT COUNT(*) FROM `retailflow_source.brands`) AS actual
UNION ALL
SELECT 'brands: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.brands`) AS actual
UNION ALL
SELECT 'suppliers: rows' AS check_name, 20 AS expected, (SELECT COUNT(*) FROM `retailflow_source.suppliers`) AS actual
UNION ALL
SELECT 'suppliers: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.suppliers`) AS actual
UNION ALL
SELECT 'stores: rows' AS check_name, 12 AS expected, (SELECT COUNT(*) FROM `retailflow_source.stores`) AS actual
UNION ALL
SELECT 'stores: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.stores`) AS actual
UNION ALL
SELECT 'customers: rows' AS check_name, 5000 AS expected, (SELECT COUNT(*) FROM `retailflow_source.customers`) AS actual
UNION ALL
SELECT 'customers: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.customers`) AS actual
UNION ALL
SELECT 'products: rows' AS check_name, 1000 AS expected, (SELECT COUNT(*) FROM `retailflow_source.products`) AS actual
UNION ALL
SELECT 'products: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.products`) AS actual
UNION ALL
SELECT 'promotions: rows' AS check_name, 3 AS expected, (SELECT COUNT(*) FROM `retailflow_source.promotions`) AS actual
UNION ALL
SELECT 'promotions: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.promotions`) AS actual
UNION ALL
SELECT 'exchange_rates: rows' AS check_name, 168 AS expected, (SELECT COUNT(*) FROM `retailflow_source.exchange_rates`) AS actual
UNION ALL
SELECT 'exchange_rates: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.exchange_rates`) AS actual
UNION ALL
SELECT 'order_items: rows' AS check_name, 50000 AS expected, (SELECT COUNT(*) FROM `retailflow_source.order_items`) AS actual
UNION ALL
SELECT 'order_items: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.order_items`) AS actual
UNION ALL
SELECT 'orders: rows' AS check_name, 20000 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders`) AS actual
UNION ALL
SELECT 'orders: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.orders`) AS actual
UNION ALL
SELECT 'order_promotions: rows' AS check_name, 2000 AS expected, (SELECT COUNT(*) FROM `retailflow_source.order_promotions`) AS actual
UNION ALL
SELECT 'order_promotions: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.order_promotions`) AS actual
UNION ALL
SELECT 'payments: rows' AS check_name, 20800 AS expected, (SELECT COUNT(*) FROM `retailflow_source.payments`) AS actual
UNION ALL
SELECT 'payments: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.payments`) AS actual
UNION ALL
SELECT 'inventory: rows' AS check_name, 8400 AS expected, (SELECT COUNT(*) FROM `retailflow_source.inventory`) AS actual
UNION ALL
SELECT 'inventory: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.inventory`) AS actual
UNION ALL
SELECT 'returns: rows' AS check_name, 500 AS expected, (SELECT COUNT(*) FROM `retailflow_source.returns`) AS actual
UNION ALL
SELECT 'returns: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.returns`) AS actual
UNION ALL
SELECT 'customer_events: rows' AS check_name, 12000 AS expected, (SELECT COUNT(*) FROM `retailflow_source.customer_events`) AS actual
UNION ALL
SELECT 'customer_events: invalid lineage' AS check_name, 0 AS expected, (SELECT COUNTIF(batch_id IS DISTINCT FROM 'BATCH_001' OR source_operation IS DISTINCT FROM 'INSERT' OR source_available_at IS DISTINCT FROM batch_timestamp) + COUNT(*) - COUNT(DISTINCT source_record_id) FROM `retailflow_source.customer_events`) AS actual
UNION ALL
SELECT 'categories.parent_category_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.categories` AS child LEFT JOIN `retailflow_source.categories` AS parent ON child.parent_category_id = parent.category_id WHERE parent.category_id IS NULL AND child.parent_category_id IS NOT NULL) AS actual
UNION ALL
SELECT 'products.category_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.products` AS child LEFT JOIN `retailflow_source.categories` AS parent ON child.category_id = parent.category_id WHERE parent.category_id IS NULL) AS actual
UNION ALL
SELECT 'products.brand_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.products` AS child LEFT JOIN `retailflow_source.brands` AS parent ON child.brand_id = parent.brand_id WHERE parent.brand_id IS NULL) AS actual
UNION ALL
SELECT 'products.supplier_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.products` AS child LEFT JOIN `retailflow_source.suppliers` AS parent ON child.supplier_id = parent.supplier_id WHERE parent.supplier_id IS NULL) AS actual
UNION ALL
SELECT 'orders.customer_id: orphan' AS check_name, 1 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS child LEFT JOIN `retailflow_source.customers` AS parent ON child.customer_id = parent.customer_id WHERE parent.customer_id IS NULL) AS actual
UNION ALL
SELECT 'orders.store_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS child LEFT JOIN `retailflow_source.stores` AS parent ON child.store_id = parent.store_id WHERE parent.store_id IS NULL) AS actual
UNION ALL
SELECT 'order_items.order_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.order_items` AS child LEFT JOIN `retailflow_source.orders` AS parent ON child.order_id = parent.order_id WHERE parent.order_id IS NULL) AS actual
UNION ALL
SELECT 'order_items.product_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.order_items` AS child LEFT JOIN `retailflow_source.products` AS parent ON child.product_id = parent.product_id WHERE parent.product_id IS NULL) AS actual
UNION ALL
SELECT 'payments.order_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.payments` AS child LEFT JOIN `retailflow_source.orders` AS parent ON child.order_id = parent.order_id WHERE parent.order_id IS NULL) AS actual
UNION ALL
SELECT 'inventory.store_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.inventory` AS child LEFT JOIN `retailflow_source.stores` AS parent ON child.store_id = parent.store_id WHERE parent.store_id IS NULL) AS actual
UNION ALL
SELECT 'inventory.product_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.inventory` AS child LEFT JOIN `retailflow_source.products` AS parent ON child.product_id = parent.product_id WHERE parent.product_id IS NULL) AS actual
UNION ALL
SELECT 'returns.order_item_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.returns` AS child LEFT JOIN `retailflow_source.order_items` AS parent ON child.order_item_id = parent.order_item_id WHERE parent.order_item_id IS NULL) AS actual
UNION ALL
SELECT 'order_promotions.order_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.order_promotions` AS child LEFT JOIN `retailflow_source.orders` AS parent ON child.order_id = parent.order_id WHERE parent.order_id IS NULL) AS actual
UNION ALL
SELECT 'order_promotions.promotion_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.order_promotions` AS child LEFT JOIN `retailflow_source.promotions` AS parent ON child.promotion_id = parent.promotion_id WHERE parent.promotion_id IS NULL) AS actual
UNION ALL
SELECT 'customer_events.customer_id: orphan' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.customer_events` AS child LEFT JOIN `retailflow_source.customers` AS parent ON child.customer_id = parent.customer_id WHERE parent.customer_id IS NULL) AS actual
UNION ALL
SELECT 'customers: missing email' AS check_name, 100 AS expected, (SELECT COUNTIF(email IS NULL) FROM `retailflow_source.customers`) AS actual
UNION ALL
SELECT 'customers: malformed email' AS check_name, 50 AS expected, (SELECT COUNTIF(email IS NOT NULL AND NOT REGEXP_CONTAINS(email, r'^[^@\s]+@[^@\s]+\.[^@\s]+$')) FROM `retailflow_source.customers`) AS actual
UNION ALL
SELECT 'products: missing description' AS check_name, 10 AS expected, (SELECT COUNTIF(description IS NULL) FROM `retailflow_source.products`) AS actual
UNION ALL
SELECT 'suppliers: missing contact' AS check_name, 1 AS expected, (SELECT COUNTIF(contact_email IS NULL) FROM `retailflow_source.suppliers`) AS actual
UNION ALL
SELECT 'order items: invalid quantity or total' AS check_name, 1 AS expected, (SELECT COUNTIF(quantity <= 0 OR line_total != quantity * unit_price - discount_amount + tax_amount) FROM `retailflow_source.order_items`) AS actual
UNION ALL
SELECT 'orders: header total mismatch' AS check_name, 1 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS o JOIN (SELECT order_id, SUM(line_total) AS line_total, SUM(tax_amount) AS tax FROM `retailflow_source.order_items` GROUP BY order_id) AS i USING (order_id) WHERE o.order_total != i.line_total - o.discount_amount + o.shipping_amount OR o.tax_amount != i.tax) AS actual
UNION ALL
SELECT 'orders: store currency or channel mismatch' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS o JOIN `retailflow_source.stores` AS s USING (store_id) WHERE o.currency != s.currency OR o.order_channel != s.channel) AS actual
UNION ALL
SELECT 'orders: missing FX' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS o LEFT JOIN `retailflow_source.exchange_rates` AS fx ON fx.rate_date = DATE(o.order_date) AND fx.from_currency = o.currency AND fx.to_currency = 'USD' WHERE fx.exchange_rate IS NULL) AS actual
UNION ALL
SELECT 'order promotions: header discount mismatch' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS o LEFT JOIN (SELECT order_id, SUM(applied_discount_amount) AS applied FROM `retailflow_source.order_promotions` GROUP BY order_id) AS p USING (order_id) WHERE o.discount_amount != COALESCE(p.applied, 0)) AS actual
UNION ALL
SELECT 'payments: successful receipt mismatch' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.orders` AS o LEFT JOIN (SELECT order_id, SUM(payment_amount) AS collected FROM `retailflow_source.payments` WHERE payment_status = 'SUCCESS' GROUP BY order_id) AS p USING (order_id) WHERE COALESCE(p.collected, 0) != IF(o.order_status = 'COMPLETED', o.order_total, 0)) AS actual
UNION ALL
SELECT 'returns: invalid reference, quantity or credit' AS check_name, 0 AS expected, (SELECT COUNT(*) FROM `retailflow_source.returns` AS r JOIN `retailflow_source.order_items` AS i USING (order_item_id) JOIN `retailflow_source.orders` AS o ON r.order_id = o.order_id WHERE r.order_id != i.order_id OR r.product_id != i.product_id OR r.return_quantity NOT BETWEEN 1 AND i.quantity OR o.fulfilled_at IS NULL OR r.completed_at < o.fulfilled_at OR r.refund_amount != ROUND(r.return_quantity * (i.unit_price - i.discount_amount / NULLIF(i.quantity, 0)), 2)) AS actual
UNION ALL
SELECT 'inventory: invalid stock' AS check_name, 0 AS expected, (SELECT COUNTIF(quantity_on_hand < 0 OR reserved_quantity NOT BETWEEN 0 AND quantity_on_hand) FROM `retailflow_source.inventory`) AS actual
UNION ALL
SELECT 'events: missing nested session or product' AS check_name, 0 AS expected, (SELECT COUNTIF(JSON_VALUE(event_payload, '$.session.session_id') IS NULL OR JSON_VALUE(event_payload, '$.products[0].product_id') IS NULL) FROM `retailflow_source.customer_events`) AS actual;

SELECT check_name, expected, actual
FROM validation_results
WHERE actual IS DISTINCT FROM expected
ORDER BY check_name;

ASSERT (SELECT COUNTIF(actual IS DISTINCT FROM expected) = 0 FROM validation_results)
AS 'BATCH_001 fixture checks failed. Inspect the preceding result set.';
