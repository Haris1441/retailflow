-- Phase 15 · Let dbt create isolated schemas for CI and prefixed builds. Run once as ACCOUNTADMIN.
-- dbt Cloud CI builds a pull request into dbt_cloud_pr_<job>_<pr>_<LAYER> schemas, and a build
-- with RETAILFLOW_SCHEMA_PREFIX set creates <PREFIX>_<LAYER> schemas (see
-- macros/generate_schema_name.sql). RETAIL_DBT_ROLE owns the schemas it creates, so it can also
-- drop them. The real layer schemas (STAGING, SILVER, DATA_QUALITY, GOLD) are unchanged.
USE ROLE ACCOUNTADMIN;

GRANT CREATE SCHEMA ON DATABASE RETAIL_DWH TO ROLE RETAIL_DBT_ROLE;

SHOW GRANTS TO ROLE RETAIL_DBT_ROLE;

-- Housekeeping: list isolated schemas left behind by closed pull requests or old dev builds.
-- dbt Cloud removes its PR schemas when the pull request closes; anything listed here a day
-- after the PR closed can be dropped with DROP SCHEMA RETAIL_DWH.<name>;
SELECT SCHEMA_NAME, SCHEMA_OWNER, CREATED
FROM RETAIL_DWH.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME ILIKE 'DBT_CLOUD_PR_%' OR SCHEMA_NAME ILIKE 'DEV_%'
ORDER BY CREATED;
