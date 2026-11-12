-- Phase 8: let the dbt Cloud role build Silver tables and seeds.
-- Run once in Snowsight as ACCOUNTADMIN (or the role that owns RETAIL_DWH) before
--   dbt build --select tag:silver
-- dbt reads STAGING views (already granted in grant_dbt.sql) and writes only to SILVER.

USE ROLE ACCOUNTADMIN;

GRANT USAGE ON SCHEMA RETAIL_DWH.SILVER TO ROLE RETAIL_DBT_ROLE;
GRANT CREATE TABLE ON SCHEMA RETAIL_DWH.SILVER TO ROLE RETAIL_DBT_ROLE;
GRANT CREATE VIEW ON SCHEMA RETAIL_DWH.SILVER TO ROLE RETAIL_DBT_ROLE;

SHOW GRANTS TO ROLE RETAIL_DBT_ROLE;
