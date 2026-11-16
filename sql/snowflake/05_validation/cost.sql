-- Phase 15 · Cost review. Run in Snowsight as ACCOUNTADMIN (ACCOUNT_USAGE views need it).
-- ACCOUNT_USAGE lags by up to about 3 hours. Credits are converted to money at your contract
-- rate; the trial balance itself is under Admin > Billing & Terms.
USE ROLE ACCOUNTADMIN;

-- 1. Warehouses: size and auto-suspend. A small warehouse that suspends after 60 s or less is
--    the main cost control for a project like this.
SHOW WAREHOUSES;
SELECT "name" AS warehouse, "size", "auto_suspend" AS auto_suspend_seconds, "auto_resume", "state"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 2. Total credits by service type, last 30 days (compute, cloud services, serverless).
SELECT SERVICE_TYPE,
       ROUND(SUM(CREDITS_USED_COMPUTE), 3)        AS compute_credits,
       ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 3) AS cloud_services_credits,
       ROUND(SUM(CREDITS_ADJUSTMENT_CLOUD_SERVICES), 3) AS cloud_services_adjustment,
       ROUND(SUM(CREDITS_BILLED), 3)              AS credits_billed
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE USAGE_DATE >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY SERVICE_TYPE
ORDER BY credits_billed DESC;

-- 3. Warehouse credits per day, last 30 days.
SELECT TO_DATE(START_TIME) AS usage_date, WAREHOUSE_NAME,
       ROUND(SUM(CREDITS_USED), 3) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1, 2;

-- 4. Who uses the warehouse: execution time by role and by query tag, last 30 days.
--    Roles: RETAIL_DBT_ROLE = dbt Cloud, RETAILFLOW_LOADER = Python loaders, FIVETRAN_ROLE = Fivetran.
--    Query tags: retailflow_phase_5 / _6 / _14 = the Python loaders and the landing pipeline.
SELECT ROLE_NAME, NULLIF(QUERY_TAG, '') AS query_tag, COUNT(*) AS queries,
       ROUND(SUM(TOTAL_ELAPSED_TIME) / 1000 / 60, 1) AS elapsed_minutes,
       ROUND(SUM(EXECUTION_TIME) / 1000 / 60, 1)     AS execution_minutes
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND WAREHOUSE_NAME = 'RETAILFLOW_WH'
GROUP BY 1, 2
ORDER BY execution_minutes DESC
LIMIT 20;

-- 5. The ten slowest dbt models (by their CREATE statement), last 30 days: where tuning would pay.
SELECT REGEXP_SUBSTR(QUERY_TEXT, 'RETAIL_DWH\\.[A-Z_0-9]+\\.[A-Z_0-9]+', 1, 1, 'i') AS object_built,
       COUNT(*) AS builds,
       ROUND(AVG(EXECUTION_TIME) / 1000, 1) AS avg_seconds,
       ROUND(MAX(EXECUTION_TIME) / 1000, 1) AS max_seconds
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND ROLE_NAME = 'RETAIL_DBT_ROLE'
  AND QUERY_TYPE IN ('CREATE_TABLE_AS_SELECT', 'CREATE_VIEW', 'INSERT', 'DELETE', 'MERGE')
GROUP BY 1
ORDER BY avg_seconds DESC
LIMIT 10;

-- 6. Storage: the RetailFlow database (active, Time Travel and Fail-safe bytes), per schema.
SELECT TABLE_SCHEMA,
       COUNT(*) AS tables,
       ROUND(SUM(ACTIVE_BYTES) / POWER(1024, 2), 1)      AS active_mb,
       ROUND(SUM(TIME_TRAVEL_BYTES) / POWER(1024, 2), 1) AS time_travel_mb,
       ROUND(SUM(FAILSAFE_BYTES) / POWER(1024, 2), 1)    AS failsafe_mb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE TABLE_CATALOG = 'RETAIL_DWH' AND NOT DELETED
GROUP BY 1
ORDER BY active_mb DESC;

-- 7. Leftover isolated schemas from CI or prefixed builds (should be empty or recent).
SELECT SCHEMA_NAME, CREATED
FROM RETAIL_DWH.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME ILIKE 'DBT_CLOUD_PR_%' OR SCHEMA_NAME ILIKE 'DEV_%'
ORDER BY CREATED;
