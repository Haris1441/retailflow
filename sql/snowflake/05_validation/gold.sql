-- Phase 12 Gold validation. Run in Snowsight after
--   dbt build --select tag:staging tag:silver tag:data_quality tag:gold
-- Expected values were recomputed independently from the fixture generation rules
-- (scratch simulation of DATA_GENERATION_MANIFEST.md), not read back from Gold.
-- Compare money to the cent; differences of 0.01 can come from rounding order.

USE DATABASE RETAIL_DWH;

-- 1. Row counts. Expected:
--    dim_date 1,096 · dim_customer 5,029 (5,028 versions + UNKNOWN) · dim_product 1,012 · dim_store 13
--    fct_sales 52,110 (BIGQUERY 52,094 + MOCK_API 16; orders 10, 20 and 30 excluded)
--    fct_returns 501 · fct_payments 22,906 · fct_inventory_snapshot 8,408
SELECT 'dim_date' AS gold_table, COUNT(*) AS row_count FROM GOLD.DIM_DATE
UNION ALL SELECT 'dim_customer', COUNT(*) FROM GOLD.DIM_CUSTOMER
UNION ALL SELECT 'dim_product', COUNT(*) FROM GOLD.DIM_PRODUCT
UNION ALL SELECT 'dim_store', COUNT(*) FROM GOLD.DIM_STORE
UNION ALL SELECT 'fct_sales', COUNT(*) FROM GOLD.FCT_SALES
UNION ALL SELECT 'fct_returns', COUNT(*) FROM GOLD.FCT_RETURNS
UNION ALL SELECT 'fct_payments', COUNT(*) FROM GOLD.FCT_PAYMENTS
UNION ALL SELECT 'fct_inventory_snapshot', COUNT(*) FROM GOLD.FCT_INVENTORY_SNAPSHOT;

-- 2. Recognized sales by source. Expected:
--    BIGQUERY  orders 20,598 · lines 48,096 · units 94,092 · merchandise USD 9,669,722.83 · cost USD 5,743,849.80
--    MOCK_API  orders 8      · lines 16     · units 16     · merchandise USD 160.00       · cost USD 612.80
--    unknown customer, unknown product and missing USD: 0 everywhere
SELECT source_system,
       COUNT(DISTINCT order_key) AS recognized_orders,
       COUNT(*) AS recognized_lines,
       SUM(quantity) AS units,
       ROUND(SUM(booked_merchandise_usd), 2) AS merchandise_usd,
       ROUND(SUM(cost_usd), 2) AS cost_usd,
       COUNT_IF(customer_sk = 'UNKNOWN') AS unknown_customer_lines,
       COUNT_IF(product_sk = 'UNKNOWN') AS unknown_product_lines,
       COUNT_IF(NOT has_usd) AS lines_missing_usd
FROM GOLD.FCT_SALES
WHERE is_recognized
GROUP BY 1
ORDER BY 1;

-- 3. Recognized merchandise in local currency (aggregate only within a currency). Expected:
--    AED 9,244,588.13 · GBP 1,880,921.68 · PKR 651,332,244.00 · USD 2,495,393.65
SELECT currency, ROUND(SUM(booked_merchandise_local), 2) AS merchandise_local
FROM GOLD.FCT_SALES
WHERE is_recognized
GROUP BY 1
ORDER BY 1;

-- 4. Monthly revenue. Expected:
--    month    merchandise   credits    net revenue   net cost      gross margin  margin   orders  AOV     MoM
--    2025-01  9,217,184.19  45,645.96  9,171,538.24  5,449,034.00  3,722,504.24  40.59 %  17,812  517.47  -
--    2025-02    452,698.64   7,513.40    445,185.23    263,934.00    181,251.23  40.71 %   2,794  162.03  -95.15 %
SELECT year_month,
       ROUND(recognized_merchandise_usd, 2) AS merchandise_usd,
       ROUND(merchandise_credits_usd, 2) AS credits_usd,
       ROUND(net_revenue_usd, 2) AS net_revenue_usd,
       ROUND(net_cost_usd, 2) AS net_cost_usd,
       ROUND(gross_margin_usd, 2) AS gross_margin_usd,
       ROUND(gross_margin_pct * 100, 2) AS gross_margin_pct,
       recognized_orders,
       ROUND(average_order_value_usd, 2) AS aov_usd,
       ROUND(mom_net_revenue_growth * 100, 2) AS mom_growth_pct
FROM GOLD.GOLD_MONTHLY_REVENUE
ORDER BY year_month;

-- 5. Daily sales add up to the monthly totals. Expected: the two rows match check 4
--    (9,217,184.19 and 452,698.64) and lines_missing_usd is 0.
SELECT TO_CHAR(fulfillment_date, 'YYYY-MM') AS year_month,
       COUNT(*) AS sales_days,
       ROUND(SUM(recognized_merchandise_usd), 2) AS merchandise_usd,
       SUM(lines_missing_usd) AS lines_missing_usd
FROM GOLD.GOLD_DAILY_SALES
GROUP BY 1
ORDER BY 1;

-- 6. Segments over all months. Expected:
--    CATEGORY      Electronics > Computers > Laptops 3,296,312.56 · Clothing > Men > Jackets 3,183,908.29
--                  Home > Kitchen > Appliances 3,189,661.98
--    LOYALTY_TIER  GOLD 3,222,097.52 · SILVER 3,220,685.48 · STANDARD 3,226,939.84 · NO_TIER 160.00 (API)
--    COUNTRY_CHANNEL  AE MOBILE 783,732.35 · AE STORE 688,454.22 · AE WEB 1,045,377.40
--                     GB MOBILE 837,721.32 · GB STORE 1,047,454.97 · GB WEB 471,367.89
--                     PK MOBILE 856,228.73 · PK STORE 621,059.68 · PK WEB 823,092.62
--                     US MOBILE 1,041,298.75 · US STORE 934,063.10 · US WEB 520,031.80
SELECT segment_type, segment_value, ROUND(SUM(recognized_merchandise_usd), 2) AS merchandise_usd
FROM GOLD.GOLD_SALES_BY_SEGMENT_MONTH
WHERE segment_type IN ('CATEGORY', 'LOYALTY_TIER', 'COUNTRY_CHANNEL')
GROUP BY 1, 2
ORDER BY 1, 2;

-- 7. Top 10 products by recognized merchandise (product id breaks ties). Expected:
--    1: 104,338.84 · 837: 24,156.02 · 611: 23,742.46 · 457: 23,703.63 · 801: 23,684.79
--    77: 23,678.87 · 41: 23,486.41 · 883: 23,345.57 · 231: 23,323.68 · 195: 23,310.61
SELECT p.product_id, ROUND(SUM(s.booked_merchandise_usd), 2) AS merchandise_usd
FROM GOLD.FCT_SALES AS s
JOIN GOLD.DIM_PRODUCT AS p ON p.product_sk = s.product_sk
WHERE s.is_recognized
GROUP BY 1
ORDER BY merchandise_usd DESC, p.product_id
LIMIT 10;

-- 8. Customer lifetime value. Expected 4,864 customers (4,856 BIGQUERY + 8 MOCK_API). Top 5:
--    BIGQUERY:1585 4,013.77 · :585 3,999.05 · :2585 3,911.13 · :4585 3,813.90 · :3585 3,783.01
SELECT COUNT(*) AS customers, COUNT_IF(source_system = 'BIGQUERY') AS bigquery_customers
FROM GOLD.GOLD_CUSTOMER_LIFETIME_VALUE;

SELECT customer_key, fulfilled_orders, ROUND(lifetime_value_usd, 2) AS lifetime_value_usd
FROM GOLD.GOLD_CUSTOMER_LIFETIME_VALUE
ORDER BY lifetime_value_usd DESC, customer_key
LIMIT 5;

-- 9. Rates. Expected:
--    return rate   501 returned units / 94,108 fulfilled units = 0.005324
--    refund rate   25.48 refunded / 10,178,600.89 collected USD = 0.0000025
--    stockout rate 742 / 8,408 snapshots = 0.088249
WITH rates AS (
    SELECT 'return rate' AS kpi,
           (SELECT SUM(return_quantity) FROM GOLD.FCT_RETURNS WHERE is_completed) AS numerator,
           (SELECT SUM(quantity) FROM GOLD.FCT_SALES WHERE is_recognized) AS denominator
    UNION ALL
    SELECT 'refund rate',
           (SELECT SUM(payment_amount_usd) FROM GOLD.FCT_PAYMENTS WHERE is_successful AND payment_type = 'REFUND'),
           (SELECT SUM(payment_amount_usd) FROM GOLD.FCT_PAYMENTS WHERE is_successful AND payment_type = 'CHARGE')
    UNION ALL
    SELECT 'stockout rate',
           (SELECT COUNT_IF(is_stockout) FROM GOLD.FCT_INVENTORY_SNAPSHOT),
           (SELECT COUNT(*) FROM GOLD.FCT_INVENTORY_SNAPSHOT)
)
SELECT kpi,
       ROUND(numerator, 2) AS numerator,
       ROUND(denominator, 2) AS denominator,
       ROUND(numerator / denominator, 8) AS rate
FROM rates;

-- 10. Point in time: the late GOLD tier of customer 12 (effective 2025-01-13) is used for its later
--     orders only. Expected: STANDARD for orders before 2025-01-13, GOLD after.
SELECT s.order_id, s.order_at, c.loyalty_tier AS tier_at_order, c.version_number
FROM GOLD.FCT_SALES AS s
JOIN GOLD.DIM_CUSTOMER AS c ON c.customer_sk = s.customer_sk
WHERE c.customer_key = 'BIGQUERY:12'
GROUP BY 1, 2, 3, 4
ORDER BY s.order_at;
