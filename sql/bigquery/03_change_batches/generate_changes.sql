-- Append-only change fixtures. Use the BATCH_001 base date.
DECLARE fixture_base_date DATE DEFAULT (
  SELECT DATE_SUB(DATE(MIN(source_available_at)), INTERVAL 42 DAY)
  FROM `retailflow_source.categories` WHERE batch_id = 'BATCH_001'
);

ASSERT fixture_base_date IS NOT NULL AS 'Validate BATCH_001 before generating changes.';

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_002` AS
WITH events AS (
SELECT 'customers' AS entity, CAST(5001 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 43 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (5001 AS customer_id, 'customer05001@example.invalid' AS email, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 43 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id = 2
UNION ALL
SELECT 'products' AS entity, CAST(1001 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 43 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT p.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (1001 AS product_id, 'RF-01001' AS sku, 'Laptop Special Edition' AS product_name, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 43 DAY)) AS created_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 43 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.products` AS p WHERE product_id = 1
UNION ALL
SELECT 'orders' AS entity, CAST(n AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS effective_at, 1 AS delivery_sequence,
       'new_order' AS scenario, TO_JSON(STRUCT(n AS order_id, IF(n = 20001, 5001, 1 + MOD(n, 5000)) AS customer_id, 1 AS store_id,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS order_date, 'COMPLETED' AS order_status, 'STORE' AS order_channel,
         'USD' AS currency, p.base_price AS order_total, NUMERIC '0' AS discount_amount,
         NUMERIC '0' AS shipping_amount, NUMERIC '0' AS tax_amount, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS created_at,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 45 DAY)) AS updated_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 45 DAY)) AS fulfilled_at, FALSE AS is_deleted)) AS payload
FROM UNNEST(GENERATE_ARRAY(20001, 22000)) AS n
JOIN `retailflow_source.products` AS p ON p.product_id = 1
UNION ALL
SELECT 'order_items' AS entity, CAST(n + 100000 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS effective_at, 1 AS delivery_sequence,
       'new_order' AS scenario, TO_JSON(STRUCT(n + 100000 AS order_item_id, n AS order_id, IF(n = 20001, 1001, 1) AS product_id,
         1 AS quantity, p.base_price AS unit_price, NUMERIC '0' AS discount_amount,
         NUMERIC '0' AS tax_amount, p.base_price AS line_total,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS created_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS updated_at)) AS payload
FROM UNNEST(GENERATE_ARRAY(20001, 22000)) AS n
JOIN `retailflow_source.products` AS p ON p.product_id = 1
UNION ALL
SELECT 'payments' AS entity, CAST(n + 200000 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS effective_at, 1 AS delivery_sequence,
       'new_order' AS scenario, TO_JSON(STRUCT(n + 200000 AS payment_id, n AS order_id, 'CARD' AS payment_method,
         'SUCCESS' AS payment_status, p.base_price AS payment_amount, 'USD' AS payment_currency,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS payment_timestamp, FORMAT('RF-CHANGE-%d', n) AS transaction_reference,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 44 DAY)) AS updated_at, 'CHARGE' AS payment_type)) AS payload
FROM UNNEST(GENERATE_ARRAY(20001, 22000)) AS n
JOIN `retailflow_source.products` AS p ON p.product_id = 1
UNION ALL
SELECT 'exchange_rates', FORMAT('%t:%s:USD', rate_date, currency), 'INSERT',
       TIMESTAMP(rate_date), 1, 'extended_fx',
       TO_JSON(STRUCT(rate_date, currency AS from_currency, 'USD' AS to_currency,
         CASE currency WHEN 'USD' THEN NUMERIC '1' WHEN 'PKR' THEN NUMERIC '0.0035'
              WHEN 'GBP' THEN NUMERIC '1.25' ELSE NUMERIC '0.2723' END AS exchange_rate,
         TIMESTAMP(rate_date) AS effective_at))
FROM UNNEST(GENERATE_DATE_ARRAY(DATE_ADD(fixture_base_date, INTERVAL 42 DAY),
                                DATE_ADD(fixture_base_date, INTERVAL 58 DAY))) AS rate_date
CROSS JOIN UNNEST(['USD', 'PKR', 'GBP', 'AED']) AS currency
)
SELECT 'BATCH_002' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 46 DAY)) AS source_available_at,
       FORMAT('BATCH_002:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_003` AS
WITH events AS (
SELECT 'customers' AS entity, CAST(customer_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('88 Revised Fixture Lane' AS address, IF(loyalty_tier = 'GOLD', 'SILVER', 'GOLD') AS loyalty_tier, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id BETWEEN 2 AND 11
UNION ALL
SELECT 'products' AS entity, CAST(product_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT p.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (base_price + NUMERIC '5' AS base_price, 7 + MOD(category_id - 6, 3) AS category_id, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.products` AS p WHERE product_id BETWEEN 2 AND 11
UNION ALL
SELECT 'orders' AS entity, CAST(order_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT o.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('COMPLETED' AS order_status, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS fulfilled_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.orders` AS o WHERE order_id BETWEEN 40 AND 10020 AND MOD(order_id, 20) = 0
UNION ALL
SELECT 'payments' AS entity, CAST(payment_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT p.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('SUCCESS' AS payment_status, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS payment_timestamp, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 47 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.payments` AS p WHERE order_id BETWEEN 40 AND 10020 AND MOD(order_id, 20) = 0 AND payment_status = 'PENDING'
)
SELECT 'BATCH_003' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 48 DAY)) AS source_available_at,
       FORMAT('BATCH_003:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_004` AS
WITH events AS (
SELECT 'orders' AS entity, CAST(order_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT o.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('CANCELED' AS order_status, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.orders` AS o WHERE order_id = 10040
UNION ALL
SELECT 'payments' AS entity, CAST(payment_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON((SELECT AS STRUCT p.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('FAILED' AS payment_status, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.payments` AS p WHERE order_id = 10040 AND payment_status = 'PENDING'
UNION ALL
SELECT 'returns' AS entity, CAST(60001 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON(STRUCT(60001 AS return_id, 4 AS order_id, i.order_item_id, i.product_id,
         1 AS return_quantity, 'CHANGED_MIND' AS return_reason, 'COMPLETED' AS return_status,
         ROUND(i.unit_price - i.discount_amount / i.quantity, 2) AS refund_amount,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 48 DAY)) AS requested_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS completed_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS updated_at)) AS payload
FROM `retailflow_source.order_items` AS i WHERE order_item_id = 10
UNION ALL
SELECT 'payments' AS entity, CAST(260001 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS effective_at, 1 AS delivery_sequence,
       'standard' AS scenario, TO_JSON(STRUCT(260001 AS payment_id, o.order_id, 'WALLET' AS payment_method,
         'SUCCESS' AS payment_status, ROUND(i.unit_price - i.discount_amount / i.quantity, 2) AS payment_amount,
         o.currency AS payment_currency, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS payment_timestamp,
         'RF-REFUND-60001' AS transaction_reference, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 49 DAY)) AS updated_at,
         'REFUND' AS payment_type, 60001 AS return_id)) AS payload
FROM `retailflow_source.orders` AS o JOIN `retailflow_source.order_items` AS i USING (order_id) WHERE i.order_item_id = 10
)
SELECT 'BATCH_004' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 50 DAY)) AS source_available_at,
       FORMAT('BATCH_004:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_005` AS
WITH events AS (
SELECT 'customer_events' AS entity, CAST(event_id AS STRING) AS business_key,
       'INSERT' AS operation, event_timestamp AS effective_at, 1 AS delivery_sequence,
       'duplicate_event' AS scenario, TO_JSON((SELECT AS STRUCT ev.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at))) AS payload
FROM `retailflow_source.customer_events` AS ev WHERE event_id BETWEEN 1 AND 288
UNION ALL
SELECT 'customers' AS entity, CAST(customer_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'blank_email' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('   ' AS email, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id = 21
UNION ALL
SELECT 'customers' AS entity, CAST(customer_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'duplicate_email' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('customer00002@example.invalid' AS email, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id = 22
UNION ALL
SELECT 'products' AS entity, CAST(product_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'negative_price' AS scenario, TO_JSON((SELECT AS STRUCT p.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (NUMERIC '-1' AS base_price, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.products` AS p WHERE product_id BETWEEN 31 AND 40
UNION ALL
SELECT 'products' AS entity, CAST(product_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'missing_category' AS scenario, TO_JSON((SELECT AS STRUCT p.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (999999 AS category_id, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.products` AS p WHERE product_id BETWEEN 41 AND 45
UNION ALL
SELECT 'categories' AS entity, CAST(category_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'category_cycle' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (7 AS parent_category_id, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.categories` AS c WHERE category_id = 1
UNION ALL
SELECT 'inventory' AS entity, CAST(inventory_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'negative_stock' AS scenario, TO_JSON((SELECT AS STRUCT i.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (-1 AS quantity_on_hand, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.inventory` AS i WHERE store_id = 1 AND product_id = 1 AND snapshot_date = fixture_base_date
UNION ALL
SELECT 'returns' AS entity, CAST(60002 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS effective_at, 1 AS delivery_sequence,
       'excess_return' AS scenario, TO_JSON((SELECT AS STRUCT r.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (60002 AS return_id, 99 AS return_quantity, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS requested_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS completed_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 51 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.returns` AS r WHERE return_id = 7
)
SELECT 'BATCH_005' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 52 DAY)) AS source_available_at,
       FORMAT('BATCH_005:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_006` AS
WITH events AS (
SELECT 'orders' AS entity, CAST(n AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS effective_at, 1 AS delivery_sequence,
       'late_order' AS scenario, TO_JSON(STRUCT(n AS order_id, 1 + MOD(n, 5000) AS customer_id, 1 AS store_id,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS order_date, 'COMPLETED' AS order_status, 'STORE' AS order_channel,
         'USD' AS currency, p.base_price AS order_total, NUMERIC '0' AS discount_amount,
         NUMERIC '0' AS shipping_amount, NUMERIC '0' AS tax_amount, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS created_at,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 10 DAY)) AS updated_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 10 DAY)) AS fulfilled_at, FALSE AS is_deleted)) AS payload
FROM UNNEST(GENERATE_ARRAY(22001, 22100)) AS n
JOIN `retailflow_source.products` AS p ON p.product_id = 1
UNION ALL
SELECT 'order_items' AS entity, CAST(n + 100000 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS effective_at, 1 AS delivery_sequence,
       'late_order' AS scenario, TO_JSON(STRUCT(n + 100000 AS order_item_id, n AS order_id, 1 AS product_id,
         1 AS quantity, p.base_price AS unit_price, NUMERIC '0' AS discount_amount,
         NUMERIC '0' AS tax_amount, p.base_price AS line_total,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS created_at, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS updated_at)) AS payload
FROM UNNEST(GENERATE_ARRAY(22001, 22100)) AS n
JOIN `retailflow_source.products` AS p ON p.product_id = 1
UNION ALL
SELECT 'payments' AS entity, CAST(n + 200000 AS STRING) AS business_key,
       'INSERT' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS effective_at, 1 AS delivery_sequence,
       'late_order' AS scenario, TO_JSON(STRUCT(n + 200000 AS payment_id, n AS order_id, 'CARD' AS payment_method,
         'SUCCESS' AS payment_status, p.base_price AS payment_amount, 'USD' AS payment_currency,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS payment_timestamp, FORMAT('RF-CHANGE-%d', n) AS transaction_reference,
         TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 9 DAY)) AS updated_at, 'CHARGE' AS payment_type)) AS payload
FROM UNNEST(GENERATE_ARRAY(22001, 22100)) AS n
JOIN `retailflow_source.products` AS p ON p.product_id = 1
UNION ALL
SELECT 'customers' AS entity, CAST(customer_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 12 DAY)) AS effective_at, 1 AS delivery_sequence,
       'late_dimension' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE ('GOLD' AS loyalty_tier, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 12 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id = 12
UNION ALL
SELECT 'exchange_rates' AS entity, CAST(FORMAT('%t:%s:%s', rate_date, from_currency, to_currency) AS STRING) AS business_key,
       'UPDATE' AS operation, effective_at AS effective_at, 1 AS delivery_sequence,
       'late_fx' AS scenario, TO_JSON((SELECT AS STRUCT fx.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (exchange_rate + NUMERIC '0.0001' AS exchange_rate))) AS payload
FROM `retailflow_source.exchange_rates` AS fx WHERE rate_date = DATE_ADD(fixture_base_date, INTERVAL 9 DAY) AND from_currency = 'PKR'
)
SELECT 'BATCH_006' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 54 DAY)) AS source_available_at,
       FORMAT('BATCH_006:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_007` AS
WITH events AS (
SELECT 'customers' AS entity, CAST(customer_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 55 DAY)) AS effective_at, 1 AS delivery_sequence,
       'nested_addresses' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 55 DAY)) AS updated_at),
         IF(MOD(customer_id, 2) = 0, 'en', NULL) AS preferred_language,
         [STRUCT('home' AS address_id, c.address AS street, c.city, c.country, TRUE AS is_primary),
          ('pickup', '1 Collection Point', c.city, c.country, FALSE)] AS addresses)) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id BETWEEN 101 AND 110
UNION ALL
SELECT 'customer_events' AS entity, CAST(event_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 55 DAY)) AS effective_at, 1 AS delivery_sequence,
       'nested_device' AS scenario, TO_JSON((SELECT AS STRUCT ev.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (JSON_SET(event_payload, '$.device.os', 'FixtureOS') AS event_payload))) AS payload
FROM `retailflow_source.customer_events` AS ev WHERE event_id BETWEEN 301 AND 311
)
SELECT 'BATCH_007' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 56 DAY)) AS source_available_at,
       FORMAT('BATCH_007:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE TABLE IF NOT EXISTS `retailflow_source.changes_008` AS
WITH events AS (
SELECT 'customers' AS entity, CAST(customer_id AS STRING) AS business_key,
       'UPDATE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 57 DAY)) AS effective_at, 1 AS delivery_sequence,
       'soft_delete' AS scenario, TO_JSON((SELECT AS STRUCT c.* EXCEPT (source_record_id, batch_id, source_operation, source_available_at) REPLACE (TRUE AS is_deleted, 'INACTIVE' AS customer_status, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 57 DAY)) AS updated_at))) AS payload
FROM `retailflow_source.customers` AS c WHERE customer_id = 111
UNION ALL
SELECT 'customer_events' AS entity, CAST(event_id AS STRING) AS business_key,
       'DELETE' AS operation, TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 57 DAY)) AS effective_at, 1 AS delivery_sequence,
       'hard_delete_tombstone' AS scenario, TO_JSON(STRUCT(event_id)) AS payload
FROM `retailflow_source.customer_events` WHERE event_id = 401
)
SELECT 'BATCH_008' AS batch_id, entity, business_key, operation, effective_at,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 58 DAY)) AS source_available_at,
       FORMAT('BATCH_008:%s:%s:%d', entity, business_key, delivery_sequence) AS source_record_id,
       delivery_sequence, scenario, payload
FROM events;

CREATE VIEW IF NOT EXISTS `retailflow_source.source_changes` AS
SELECT * FROM `retailflow_source.changes_002`
UNION ALL
SELECT * FROM `retailflow_source.changes_003`
UNION ALL
SELECT * FROM `retailflow_source.changes_004`
UNION ALL
SELECT * FROM `retailflow_source.changes_005`
UNION ALL
SELECT * FROM `retailflow_source.changes_006`
UNION ALL
SELECT * FROM `retailflow_source.changes_007`
UNION ALL
SELECT * FROM `retailflow_source.changes_008`;

CREATE VIEW IF NOT EXISTS `retailflow_source.customer_address_examples` AS
SELECT CAST(business_key AS INT64) AS customer_id,
       JSON_VALUE(payload, '$.preferred_language') AS preferred_language,
       ARRAY(
         SELECT AS STRUCT JSON_VALUE(address, '$.address_id') AS address_id,
                JSON_VALUE(address, '$.street') AS street,
                JSON_VALUE(address, '$.city') AS city,
                JSON_VALUE(address, '$.country') AS country,
                BOOL(JSON_QUERY(address, '$.is_primary')) AS is_primary
         FROM UNNEST(JSON_QUERY_ARRAY(payload, '$.addresses')) AS address WITH OFFSET AS address_offset
         ORDER BY address_offset
       ) AS addresses
FROM `retailflow_source.changes_007` WHERE scenario = 'nested_addresses';

CREATE VIEW IF NOT EXISTS `retailflow_source.nested_order_examples` AS
WITH items AS (
  SELECT JSON_VALUE(payload, '$.order_id') AS order_id,
         ARRAY_AGG(STRUCT(payload AS item,
           ARRAY<STRUCT<discount_id STRING, amount NUMERIC>>[] AS discounts)
           ORDER BY business_key) AS items
  FROM `retailflow_source.changes_002` WHERE entity = 'order_items'
  GROUP BY order_id
),
payments AS (
  SELECT JSON_VALUE(payload, '$.order_id') AS order_id,
         ARRAY_AGG(payload ORDER BY business_key) AS payments
  FROM `retailflow_source.changes_002` WHERE entity = 'payments'
  GROUP BY order_id
)
SELECT CAST(o.business_key AS INT64) AS order_id,
       TO_JSON(STRUCT(o.payload AS order_header,
         STRUCT(JSON_VALUE(o.payload, '$.customer_id') AS customer_id) AS customer,
         i.items, STRUCT('STORE_PICKUP' AS method) AS shipping, p.payments)) AS example_payload
FROM `retailflow_source.changes_002` AS o
JOIN items AS i ON o.business_key = i.order_id
JOIN payments AS p ON o.business_key = p.order_id
WHERE o.entity = 'orders' AND o.business_key = '20001';

-- Demonstrate the hard-delete effect without mutating the source table.
CREATE VIEW IF NOT EXISTS `retailflow_source.customer_events_after_deletes` AS
SELECT baseline.*
FROM `retailflow_source.customer_events` AS baseline
LEFT JOIN `retailflow_source.changes_008` AS tombstone
  ON tombstone.entity = 'customer_events' AND tombstone.operation = 'DELETE'
  AND tombstone.business_key = CAST(baseline.event_id AS STRING)
WHERE tombstone.source_record_id IS NULL;
