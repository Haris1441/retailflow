-- Run after generate_changes.sql. Expected final assertion succeeds.
CREATE TEMP TABLE batch_mismatches AS
WITH expected AS (
  SELECT 'BATCH_002' AS batch_id, 'customers' AS entity, 'standard' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_002' AS batch_id, 'products' AS entity, 'standard' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_002' AS batch_id, 'orders' AS entity, 'new_order' AS scenario, 2000 AS row_count
  UNION ALL
  SELECT 'BATCH_002' AS batch_id, 'order_items' AS entity, 'new_order' AS scenario, 2000 AS row_count
  UNION ALL
  SELECT 'BATCH_002' AS batch_id, 'payments' AS entity, 'new_order' AS scenario, 2000 AS row_count
  UNION ALL
  SELECT 'BATCH_002' AS batch_id, 'exchange_rates' AS entity, 'extended_fx' AS scenario, 68 AS row_count
  UNION ALL
  SELECT 'BATCH_003' AS batch_id, 'customers' AS entity, 'standard' AS scenario, 10 AS row_count
  UNION ALL
  SELECT 'BATCH_003' AS batch_id, 'products' AS entity, 'standard' AS scenario, 10 AS row_count
  UNION ALL
  SELECT 'BATCH_003' AS batch_id, 'orders' AS entity, 'standard' AS scenario, 500 AS row_count
  UNION ALL
  SELECT 'BATCH_003' AS batch_id, 'payments' AS entity, 'standard' AS scenario, 500 AS row_count
  UNION ALL
  SELECT 'BATCH_004' AS batch_id, 'orders' AS entity, 'standard' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_004' AS batch_id, 'payments' AS entity, 'standard' AS scenario, 2 AS row_count
  UNION ALL
  SELECT 'BATCH_004' AS batch_id, 'returns' AS entity, 'standard' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'customer_events' AS entity, 'duplicate_event' AS scenario, 240 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'customers' AS entity, 'blank_email' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'customers' AS entity, 'duplicate_email' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'products' AS entity, 'negative_price' AS scenario, 10 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'products' AS entity, 'missing_category' AS scenario, 5 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'categories' AS entity, 'category_cycle' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'inventory' AS entity, 'negative_stock' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_005' AS batch_id, 'returns' AS entity, 'excess_return' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_006' AS batch_id, 'orders' AS entity, 'late_order' AS scenario, 100 AS row_count
  UNION ALL
  SELECT 'BATCH_006' AS batch_id, 'order_items' AS entity, 'late_order' AS scenario, 100 AS row_count
  UNION ALL
  SELECT 'BATCH_006' AS batch_id, 'payments' AS entity, 'late_order' AS scenario, 100 AS row_count
  UNION ALL
  SELECT 'BATCH_006' AS batch_id, 'customers' AS entity, 'late_dimension' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_006' AS batch_id, 'exchange_rates' AS entity, 'late_fx' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_007' AS batch_id, 'customers' AS entity, 'nested_addresses' AS scenario, 10 AS row_count
  UNION ALL
  SELECT 'BATCH_007' AS batch_id, 'customer_events' AS entity, 'nested_device' AS scenario, 10 AS row_count
  UNION ALL
  SELECT 'BATCH_008' AS batch_id, 'customers' AS entity, 'soft_delete' AS scenario, 1 AS row_count
  UNION ALL
  SELECT 'BATCH_008' AS batch_id, 'customer_events' AS entity, 'hard_delete_tombstone' AS scenario, 1 AS row_count
),
actual AS (
  SELECT batch_id, entity, scenario, COUNT(*) AS row_count
  FROM `retailflow_source.source_changes` GROUP BY batch_id, entity, scenario
)
SELECT batch_id, entity, scenario, expected.row_count AS expected_rows, actual.row_count AS actual_rows
FROM expected FULL JOIN actual USING (batch_id, entity, scenario)
WHERE expected.row_count IS DISTINCT FROM actual.row_count;

SELECT * FROM batch_mismatches ORDER BY batch_id, entity, scenario;
ASSERT (SELECT COUNT(*) = 0 FROM batch_mismatches) AS 'Change counts differ from the manifest.';

ASSERT (
  SELECT COUNT(*) = 7678 AND COUNT(*) = COUNT(DISTINCT source_record_id)
    AND COUNTIF(payload IS NULL OR effective_at IS NULL OR source_available_at IS NULL) = 0
  FROM `retailflow_source.source_changes`
) AS 'Missing payload, invalid lineage or duplicate physical record identity.';

ASSERT (
  WITH headers AS (
    SELECT batch_id, business_key AS order_id, CAST(JSON_VALUE(payload, '$.order_total') AS NUMERIC) AS total
    FROM `retailflow_source.source_changes` WHERE scenario IN ('new_order', 'late_order') AND entity = 'orders'
  ),
  lines AS (
    SELECT batch_id, JSON_VALUE(payload, '$.order_id') AS order_id,
           SUM(CAST(JSON_VALUE(payload, '$.line_total') AS NUMERIC)) AS line_total
    FROM `retailflow_source.source_changes` WHERE scenario IN ('new_order', 'late_order') AND entity = 'order_items'
    GROUP BY batch_id, order_id
  ),
  payments AS (
    SELECT batch_id, JSON_VALUE(payload, '$.order_id') AS order_id,
           SUM(CAST(JSON_VALUE(payload, '$.payment_amount') AS NUMERIC)) AS payment_amount
    FROM `retailflow_source.source_changes` WHERE scenario IN ('new_order', 'late_order') AND entity = 'payments'
    GROUP BY batch_id, order_id
  )
  SELECT COUNT(*) = 2100 AND COUNTIF(total IS NULL OR line_total IS NULL OR payment_amount IS NULL
             OR total != line_total OR line_total != payment_amount) = 0
  FROM headers FULL JOIN lines USING (batch_id, order_id)
  FULL JOIN payments USING (batch_id, order_id)
) AS 'New and late transactions must reconcile across header, line and payment.';

ASSERT (
  SELECT COUNT(*) = 240 AND COUNTIF(
    JSON_VALUE(c.payload, '$.event_id') IS DISTINCT FROM CAST(b.event_id AS STRING)
    OR JSON_VALUE(c.payload, '$.event_payload.session.session_id')
       IS DISTINCT FROM JSON_VALUE(b.event_payload, '$.session.session_id')
  ) = 0
  FROM `retailflow_source.changes_005` AS c
  LEFT JOIN `retailflow_source.customer_events` AS b ON c.business_key = CAST(b.event_id AS STRING)
  WHERE c.scenario = 'duplicate_event'
) AS 'Expected baseline event duplicates were not found.';

ASSERT (
  SELECT COUNTIF(scenario = 'late_order' AND TIMESTAMP_DIFF(source_available_at, effective_at, DAY) = 45) = 300
    AND COUNTIF(scenario = 'late_dimension' AND effective_at < source_available_at) = 1
    AND COUNTIF(scenario = 'late_fx' AND effective_at < source_available_at) = 1
  FROM `retailflow_source.changes_006`
) AS 'Late fixtures must preserve separate event and availability clocks.';

ASSERT (
  SELECT COUNT(*) = 10 AND COUNT(DISTINCT customer_id) = 10
    AND COUNTIF(ARRAY_LENGTH(addresses) = 2 AND preferred_language IS NULL) = 5
    AND COUNTIF(ARRAY_LENGTH(addresses) = 2 AND preferred_language = 'en') = 5
  FROM `retailflow_source.customer_address_examples`
) AS 'Address flattening changed parent grain or optional field coverage.';

ASSERT (
  SELECT COUNT(*) = 20
    AND COUNT(DISTINCT FORMAT('%d:%s', customer_id, address.address_id)) = 20
    AND COUNTIF(address.is_primary) = 10
  FROM `retailflow_source.customer_address_examples` CROSS JOIN UNNEST(addresses) AS address
) AS 'Address child keys or primary flags are invalid.';

ASSERT (
  SELECT COUNT(*) = 1 AND COUNTIF(ARRAY_LENGTH(JSON_QUERY_ARRAY(example_payload, '$.items')) = 1
    AND ARRAY_LENGTH(JSON_QUERY_ARRAY(example_payload, '$.payments')) = 1) = 1
  FROM `retailflow_source.nested_order_examples`
) AS 'Nested order shape is invalid.';

ASSERT (
  SELECT COUNTIF(operation = 'UPDATE' AND scenario = 'soft_delete'
    AND JSON_VALUE(payload, '$.is_deleted') = 'true') = 1
  AND COUNTIF(operation = 'DELETE' AND scenario = 'hard_delete_tombstone'
    AND JSON_VALUE(payload, '$.event_id') = '401') = 1
  FROM `retailflow_source.changes_008`
) AS 'Soft delete or hard-delete tombstone is missing.';

ASSERT (SELECT COUNT(*) = 1 FROM `retailflow_source.customer_events` WHERE event_id = 401)
AS 'Baseline event must remain available for replay.';

ASSERT (
  SELECT COUNTIF(scenario = 'blank_email' AND TRIM(JSON_VALUE(payload, '$.email')) = '') = 1
    AND COUNTIF(scenario = 'duplicate_email' AND JSON_VALUE(payload, '$.email') =
      (SELECT email FROM `retailflow_source.customers` WHERE customer_id = 2)) = 1
    AND COUNTIF(scenario = 'negative_price' AND CAST(JSON_VALUE(payload, '$.base_price') AS NUMERIC) < 0) = 10
    AND COUNTIF(scenario = 'missing_category' AND JSON_VALUE(payload, '$.category_id') = '999999') = 5
    AND COUNTIF(scenario = 'category_cycle' AND business_key = '1'
      AND JSON_VALUE(payload, '$.parent_category_id') = '7') = 1
    AND COUNTIF(scenario = 'negative_stock' AND JSON_VALUE(payload, '$.quantity_on_hand') = '-1') = 1
    AND COUNTIF(scenario = 'excess_return' AND JSON_VALUE(payload, '$.return_quantity') = '99') = 1
  FROM `retailflow_source.changes_005`
) AS 'Seeded defect payloads differ from the manifest.';

ASSERT (
  SELECT COUNTIF(scenario = 'nested_device' AND JSON_VALUE(payload, '$.event_payload.device.os') = 'FixtureOS') = 10
  FROM `retailflow_source.changes_007`
) AS 'Optional nested device field is missing.';

ASSERT (
  SELECT COUNT(*) = 11999 AND COUNTIF(event_id = 401) = 0
  FROM `retailflow_source.customer_events_after_deletes`
) AS 'Hard-delete projection must remove exactly one baseline event.';

SELECT batch_id, COUNT(*) AS physical_rows
FROM `retailflow_source.source_changes` GROUP BY batch_id ORDER BY batch_id;
