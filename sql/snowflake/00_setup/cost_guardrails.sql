-- Phase 15 · Cost guardrails. Run once as ACCOUNTADMIN. Safe to re-run.
--
-- Why (cost review, 2026-11-16, sql/snowflake/05_validation/cost.sql):
-- - 5.9 credits billed in about 10 days: COMPUTE_WH 3.95, RETAILFLOW_WH 2.43.
-- - COMPUTE_WH runs the Snowsight worksheets: 3,500+ queries but under 3 minutes of execution.
--   Almost all of its credits were idle time, because it waited 300 s before suspending after
--   every worksheet session. Lowering auto-suspend to 60 s removes most of that.
-- - RETAILFLOW_WH (dbt, loaders) is already X-Small with 60 s auto-suspend.
-- - Expected monthly use with the scheduled dbt build and CI: about 2-3 credits.
USE ROLE ACCOUNTADMIN;

-- 1. Suspend idle warehouses after 60 seconds (Snowflake bills at least 60 s per resume anyway).
ALTER WAREHOUSE COMPUTE_WH            SET AUTO_SUSPEND = 60;
ALTER WAREHOUSE SNOWFLAKE_LEARNING_WH SET AUTO_SUSPEND = 60;
ALTER WAREHOUSE RETAILFLOW_WH         SET AUTO_SUSPEND = 60;

-- 2. Monthly spending cap on the project warehouse: about 7x the expected use, so normal work
--    never reaches it, but a runaway job or a forgotten warehouse is stopped automatically.
--    The 75 % notification is emailed only if your Snowflake user has a verified email address.
CREATE RESOURCE MONITOR IF NOT EXISTS RETAILFLOW_MONTHLY
  WITH CREDIT_QUOTA = 20
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE RETAILFLOW_WH SET RESOURCE_MONITOR = RETAILFLOW_MONTHLY;

-- 3. Check.
SHOW WAREHOUSES;
SELECT "name" AS warehouse, "size", "auto_suspend" AS auto_suspend_seconds, "resource_monitor"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

SHOW RESOURCE MONITORS;

-- 4. Optional: drop the empty Fivetran schemas while Phase 7b stays parked.
--    Fivetran recreates them if the connector is resumed.
-- DROP SCHEMA IF EXISTS RETAIL_DWH.FIVETRAN_BQQ_RETAILFLOW_SOURCE;
-- DROP SCHEMA IF EXISTS RETAIL_DWH.FIVETRAN_METADATA;
