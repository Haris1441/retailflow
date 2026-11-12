-- Repair Phase 3 synthetic fixtures generated with the original event ID ranges.
-- Append-only change fixtures. Use the BATCH_001 base date.
DECLARE fixture_base_date DATE DEFAULT (
  SELECT DATE_SUB(DATE(MIN(source_available_at)), INTERVAL 42 DAY)
  FROM `retailflow_source.categories` WHERE batch_id = 'BATCH_001'
);

ASSERT fixture_base_date IS NOT NULL AS 'Validate BATCH_001 before generating changes.';

CREATE OR REPLACE TABLE `retailflow_source.changes_005` AS
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

CREATE OR REPLACE TABLE `retailflow_source.changes_007` AS
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
