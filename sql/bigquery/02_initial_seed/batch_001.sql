-- Run in the same project and location as the dedicated dataset.
-- Set once before the first run. Existing tables are retained on rerun.
DECLARE fixture_base_date DATE DEFAULT DATE '2025-01-01';

CREATE TABLE IF NOT EXISTS `retailflow_source.categories` AS
WITH fixture AS (
  SELECT category_id, category_name, parent_category_id, category_level,
         TRUE AS is_active, TIMESTAMP(fixture_base_date) AS updated_at
  FROM UNNEST([
    STRUCT(1 AS category_id, 'Electronics' AS category_name, CAST(NULL AS INT64) AS parent_category_id, 1 AS category_level),
    (2, 'Clothing', NULL, 1), (3, 'Home', NULL, 1),
    (4, 'Computers', 1, 2), (5, 'Men', 2, 2), (6, 'Kitchen', 3, 2),
    (7, 'Laptops', 4, 3), (8, 'Jackets', 5, 3), (9, 'Appliances', 6, 3)
  ])
)
SELECT fixture.*,
       CONCAT('categories:BATCH_001:', CAST(category_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.brands` AS
WITH fixture AS (
  SELECT n AS brand_id, FORMAT('RetailFlow Brand %02d', n) AS brand_name,
         ['US', 'PK', 'GB', 'AE'][OFFSET(MOD(n-1, 4))] AS origin_country,
         'ACTIVE' AS status, TIMESTAMP(fixture_base_date) AS created_at,
         TIMESTAMP(fixture_base_date) AS updated_at
  FROM UNNEST(GENERATE_ARRAY(1, 25)) AS n
)
SELECT fixture.*,
       CONCAT('brands:BATCH_001:', CAST(brand_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.suppliers` AS
WITH fixture AS (
  SELECT n AS supplier_id, FORMAT('RetailFlow Supply %02d', n) AS supplier_name,
         IF(n = 20, NULL, FORMAT('supplier%02d@example.invalid', n)) AS contact_email,
         ['US', 'PK', 'GB', 'AE'][OFFSET(MOD(n-1, 4))] AS country,
         3 + MOD(n * 7, 26) AS lead_time_days, 'ACTIVE' AS supplier_status
  FROM UNNEST(GENERATE_ARRAY(1, 20)) AS n
)
SELECT fixture.*,
       CONCAT('suppliers:BATCH_001:', CAST(supplier_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.stores` AS
WITH fixture AS (
  SELECT n AS store_id, CONCAT(market.country, ' ', channel) AS store_name,
         IF(channel = 'STORE', 'PHYSICAL', 'DIGITAL') AS store_type,
         market.country, market.region, market.city, market.currency, channel,
         DATE_SUB(fixture_base_date, INTERVAL 2 YEAR) AS opening_date,
         'ACTIVE' AS status, TIMESTAMP(fixture_base_date) AS updated_at
  FROM UNNEST([
    STRUCT('US' AS country, 'North America' AS region, 'Seattle' AS city, 'USD' AS currency),
    ('PK', 'South Asia', 'Karachi', 'PKR'), ('GB', 'Europe', 'London', 'GBP'),
    ('AE', 'Middle East', 'Dubai', 'AED')
  ]) AS market WITH OFFSET AS market_idx
  CROSS JOIN UNNEST(['STORE', 'WEB', 'MOBILE']) AS channel WITH OFFSET AS channel_idx
  CROSS JOIN UNNEST([1 + market_idx * 3 + channel_idx]) AS n
)
SELECT fixture.*,
       CONCAT('stores:BATCH_001:', CAST(store_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.customers` AS
WITH fixture AS (
  SELECT n AS customer_id,
         ['Amira', 'Daniel', 'Haris', 'Sofia', 'Noor'][OFFSET(MOD(n, 5))] AS first_name,
         ['Patel', 'Khan', 'Morgan', 'Ali', 'Rivera'][OFFSET(MOD(DIV(n, 5), 5))] AS last_name,
         CASE WHEN MOD(n, 50) = 0 THEN NULL
              WHEN MOD(n, 100) = 1 THEN FORMAT('malformed-%d', n)
              ELSE FORMAT('customer%05d@example.invalid', n) END AS email,
         FORMAT('555-01%02d', MOD(n, 100)) AS phone,
         ['F', 'M', 'UNSPECIFIED'][OFFSET(MOD(n, 3))] AS gender,
         DATE_SUB(fixture_base_date, INTERVAL (7300 + MOD(n * 17, 18250)) DAY) AS birth_date,
         DATE_SUB(fixture_base_date, INTERVAL (1 + MOD(n * 13, 730)) DAY) AS registration_date,
         'ACTIVE' AS customer_status,
         ['STANDARD', 'SILVER', 'GOLD'][OFFSET(MOD(n, 3))] AS loyalty_tier,
         market.country, market.region, market.city,
         FORMAT('%d Fixture Lane', n) AS address, market.postal_code,
         TIMESTAMP(DATE_SUB(fixture_base_date, INTERVAL (1 + MOD(n * 13, 730)) DAY)) AS created_at,
         TIMESTAMP(fixture_base_date) AS updated_at, FALSE AS is_deleted
  FROM UNNEST(GENERATE_ARRAY(1, 5000)) AS n
  CROSS JOIN UNNEST([
    [STRUCT('US' AS country, 'North America' AS region, 'Seattle' AS city, '98101' AS postal_code),
     ('PK', 'South Asia', 'Karachi', '74000'), ('GB', 'Europe', 'London', 'SW1A 1AA'),
     ('AE', 'Middle East', 'Dubai', CAST(NULL AS STRING))][OFFSET(MOD(n-1, 4))]
  ]) AS market
)
SELECT fixture.*,
       CONCAT('customers:BATCH_001:', CAST(customer_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.products` AS
WITH fixture AS (
  SELECT n AS product_id, FORMAT('RF-%05d', n) AS sku,
         FORMAT('%s %04d', ['Laptop', 'Jacket', 'Appliance'][OFFSET(MOD(n-1, 3))], n) AS product_name,
         IF(MOD(n, 100) = 0, NULL, FORMAT('Synthetic catalog item %d', n)) AS description,
         7 + MOD(n-1, 3) AS category_id, 1 + MOD(n * 11, 25) AS brand_id,
         1 + MOD(n * 7, 20) AS supplier_id,
         NUMERIC '10' + MOD(n * 37, 190) AS base_price,
         NUMERIC '5' + MOD(n * 37, 190) * NUMERIC '0.60' AS cost_price,
         'USD' AS currency, 'ACTIVE' AS product_status,
         TIMESTAMP(fixture_base_date) AS created_at, TIMESTAMP(fixture_base_date) AS updated_at
  FROM UNNEST(GENERATE_ARRAY(1, 1000)) AS n
)
SELECT fixture.*,
       CONCAT('products:BATCH_001:', CAST(product_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.promotions` AS
WITH fixture AS (
  SELECT n AS promotion_id, ['Launch Offer', 'Member Reward', 'Weekend Offer'][OFFSET(n-1)] AS promotion_name,
         'FIXED_LOCAL' AS promotion_type, NUMERIC '2' AS discount_value,
         fixture_base_date AS start_date, DATE_ADD(fixture_base_date, INTERVAL 29 DAY) AS end_date,
         'ACTIVE' AS status, TIMESTAMP(fixture_base_date) AS updated_at
  FROM UNNEST(GENERATE_ARRAY(1, 3)) AS n
)
SELECT fixture.*,
       CONCAT('promotions:BATCH_001:', CAST(promotion_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.exchange_rates` AS
WITH fixture AS (
  SELECT rate_date, c AS from_currency, 'USD' AS to_currency,
         CASE c WHEN 'USD' THEN NUMERIC '1'
                WHEN 'PKR' THEN NUMERIC '0.0035' + MOD(day_idx, 7) * NUMERIC '0.00001'
                WHEN 'GBP' THEN NUMERIC '1.25' + MOD(day_idx, 7) * NUMERIC '0.001'
                ELSE NUMERIC '0.2723' + MOD(day_idx, 7) * NUMERIC '0.00001' END AS exchange_rate,
         TIMESTAMP(rate_date) AS effective_at
  FROM UNNEST(GENERATE_DATE_ARRAY(fixture_base_date, DATE_ADD(fixture_base_date, INTERVAL 41 DAY)))
    AS rate_date WITH OFFSET AS day_idx
  CROSS JOIN UNNEST(['USD', 'PKR', 'GBP', 'AED']) AS c
)
SELECT fixture.*,
       CONCAT('exchange_rates:BATCH_001:', CAST(FORMAT('%t:%s:%s', rate_date, from_currency, to_currency) AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.order_items` AS
WITH fixture AS (
  SELECT (n-1)*3 + slot AS order_item_id, n AS order_id, p.product_id,
         IF(n = 20 AND slot = 1, 0, units) AS quantity, price AS unit_price,
         discount AS discount_amount, tax AS tax_amount,
         units * price - discount + tax AS line_total,
         TIMESTAMP_ADD(TIMESTAMP(fixture_base_date), INTERVAL MOD(n * 97, 43200) MINUTE) AS created_at,
         TIMESTAMP_ADD(TIMESTAMP(fixture_base_date), INTERVAL MOD(n * 97, 43200) MINUTE) AS updated_at
  FROM UNNEST(GENERATE_ARRAY(1, 20000)) AS n
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 2 + MOD(n, 2))) AS slot
  JOIN `retailflow_source.products` AS p
    ON p.product_id = 1 + MOD(n * 17 + IF(MOD(n, 97) = 0 AND slot = 2, 1, slot) * 29, 1000)
  CROSS JOIN UNNEST([1 + MOD(n + slot, 3)]) AS units
  CROSS JOIN UNNEST([p.base_price * [NUMERIC '1', NUMERIC '280', NUMERIC '0.80', NUMERIC '3.67'][OFFSET(MOD(DIV(MOD(n-1, 12), 3), 4))]]) AS raw_price
  CROSS JOIN UNNEST([ROUND(raw_price, 2)]) AS price
  CROSS JOIN UNNEST([IF(MOD(n + slot, 13) = 0, ROUND(units * price * NUMERIC '0.05', 2), NUMERIC '0')]) AS discount
  CROSS JOIN UNNEST([ROUND((units * price - discount) * NUMERIC '0.05', 2)]) AS tax
)
SELECT fixture.*,
       CONCAT('order_items:BATCH_001:', CAST(order_item_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.orders` AS
WITH fixture AS (
  SELECT n AS order_id, IF(n = 10, 999999, 1 + MOD((n-1) * 37, 5000)) AS customer_id,
         s.store_id, order_ts AS order_date,
         CASE WHEN MOD(n, 20) = 0 THEN 'PENDING'
              WHEN MOD(n, 20) = 1 THEN 'CANCELED'
              ELSE 'COMPLETED' END AS order_status,
         s.channel AS order_channel, s.currency,
         totals.line_total - promo_discount + shipping + IF(n = 30, NUMERIC '7', NUMERIC '0') AS order_total,
         promo_discount AS discount_amount, shipping AS shipping_amount, totals.tax AS tax_amount,
         order_ts AS created_at,
         IF(MOD(n, 20) > 1, TIMESTAMP_ADD(order_ts, INTERVAL 36 HOUR), order_ts) AS updated_at,
         IF(MOD(n, 20) > 1, TIMESTAMP_ADD(order_ts, INTERVAL 36 HOUR), NULL) AS fulfilled_at,
         FALSE AS is_deleted
  FROM (
    SELECT order_id AS n, MIN(created_at) AS order_ts, SUM(line_total) AS line_total, SUM(tax_amount) AS tax
    FROM `retailflow_source.order_items` GROUP BY order_id
  ) AS totals
  JOIN `retailflow_source.stores` AS s ON s.store_id = 1 + MOD(n-1, 12)
  CROSS JOIN UNNEST([IF(MOD(n, 10) = 0, NUMERIC '2', NUMERIC '0')]) AS promo_discount
  CROSS JOIN UNNEST([IF(s.channel = 'STORE', NUMERIC '0', NUMERIC '4')]) AS shipping
)
SELECT fixture.*,
       CONCAT('orders:BATCH_001:', CAST(order_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.order_promotions` AS
WITH fixture AS (
  SELECT order_id AS order_promotion_id, order_id,
         1 + MOD(DIV(order_id, 10), 3) AS promotion_id,
         discount_amount AS applied_discount_amount, order_date AS applied_at,
         order_date AS updated_at
  FROM `retailflow_source.orders`
  WHERE discount_amount > 0
)
SELECT fixture.*,
       CONCAT('order_promotions:BATCH_001:', CAST(order_promotion_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.payments` AS
WITH fixture AS (
  SELECT (order_id-1)*2 + attempt AS payment_id, order_id,
         ['CARD', 'WALLET', 'BANK_TRANSFER'][OFFSET(MOD(order_id, 3))] AS payment_method,
         CASE WHEN order_status = 'CANCELED' OR attempt = 2 THEN 'FAILED'
              WHEN order_status = 'PENDING' THEN 'PENDING'
              ELSE 'SUCCESS' END AS payment_status,
         order_total AS payment_amount, currency AS payment_currency,
         TIMESTAMP_ADD(order_date, INTERVAL IF(attempt = 2, 1, 2) MINUTE) AS payment_timestamp,
         FORMAT('RF-TXN-%d-%d', order_id, attempt) AS transaction_reference,
         TIMESTAMP_ADD(order_date, INTERVAL IF(attempt = 2, 1, 2) MINUTE) AS updated_at,
         'CHARGE' AS payment_type
  FROM `retailflow_source.orders`
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, IF(MOD(order_id, 25) = 0, 2, 1))) AS attempt
)
SELECT fixture.*,
       CONCAT('payments:BATCH_001:', CAST(payment_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.inventory` AS
WITH fixture AS (
  SELECT FORMAT('%d:%d:%t', store_id, product_id, snapshot_date) AS inventory_id,
         store_id, product_id, on_hand AS quantity_on_hand,
         LEAST(on_hand, MOD(store_id + product_id + day_idx, 8)) AS reserved_quantity,
         10 AS reorder_level, snapshot_date, TIMESTAMP(snapshot_date) AS updated_at
  FROM `retailflow_source.stores`
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 100)) AS product_id
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(fixture_base_date, DATE_ADD(fixture_base_date, INTERVAL 6 DAY)))
    AS snapshot_date WITH OFFSET AS day_idx
  CROSS JOIN UNNEST([MOD(store_id * 7 + product_id * 11 + day_idx * 3, 51)]) AS on_hand
)
SELECT fixture.*,
       CONCAT('inventory:BATCH_001:', CAST(inventory_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.returns` AS
WITH fixture AS (
  SELECT i.order_item_id AS return_id, o.order_id, i.order_item_id, i.product_id,
         1 AS return_quantity, 'CHANGED_MIND' AS return_reason, 'COMPLETED' AS return_status,
         ROUND((i.unit_price - i.discount_amount / i.quantity), 2) AS refund_amount,
         TIMESTAMP_ADD(o.fulfilled_at, INTERVAL 2 DAY) AS requested_at,
         TIMESTAMP_ADD(o.fulfilled_at, INTERVAL 4 DAY) AS completed_at,
         TIMESTAMP_ADD(o.fulfilled_at, INTERVAL 4 DAY) AS updated_at
  FROM `retailflow_source.orders` AS o
  JOIN `retailflow_source.order_items` AS i ON i.order_id = o.order_id AND i.order_item_id = (o.order_id-1)*3 + 1
  WHERE o.order_status = 'COMPLETED' AND o.discount_amount = 0 AND MOD(o.order_id, 40) = 3
)
SELECT fixture.*,
       CONCAT('returns:BATCH_001:', CAST(return_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;

CREATE TABLE IF NOT EXISTS `retailflow_source.customer_events` AS
WITH fixture AS (
  SELECT (session_id-1)*6 + step AS event_id, 1 + MOD(session_id * 17, 5000) AS customer_id,
         TIMESTAMP_ADD(TIMESTAMP(fixture_base_date), INTERVAL (session_id * 7 + step) MINUTE) AS event_timestamp,
         ['page_view', 'product_view', 'add_to_cart', IF(MOD(session_id, 4) = 0, 'remove_from_cart', 'checkout_started'),
          IF(MOD(session_id, 4) = 0, 'page_view', 'purchase_completed')][OFFSET(step-1)] AS event_type,
         TO_JSON(STRUCT(
           STRUCT(IF(MOD(session_id, 2) = 0, 'mobile', 'desktop') AS device_type) AS device,
           STRUCT(FORMAT('BQ-SESSION-%05d', session_id) AS session_id) AS session,
           STRUCT(IF(MOD(session_id, 3) = 0, 'email', 'organic') AS channel) AS campaign,
           [STRUCT(1 + MOD(session_id * 17, 1000) AS product_id, 'recommendation' AS placement)] AS products
         )) AS event_payload,
         'BIGQUERY_WEB_FIXTURE' AS source_system
  FROM UNNEST(GENERATE_ARRAY(1, 2400)) AS session_id
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 5)) AS step
)
SELECT fixture.*,
       CONCAT('customer_events:BATCH_001:', CAST(event_id AS STRING)) AS source_record_id,
       'BATCH_001' AS batch_id,
       'INSERT' AS source_operation,
       TIMESTAMP(DATE_ADD(fixture_base_date, INTERVAL 42 DAY)) AS source_available_at
FROM fixture;
