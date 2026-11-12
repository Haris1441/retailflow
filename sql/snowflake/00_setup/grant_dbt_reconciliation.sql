-- Phase 13: let the dbt Cloud role read the Bronze load audit for reconciliation.
-- The reconciliation tables themselves are built in DATA_QUALITY, which the role can already write.
-- Run once in Snowsight as ACCOUNTADMIN before
--   dbt build --select tag:staging tag:silver tag:data_quality tag:gold tag:reconciliation

USE ROLE ACCOUNTADMIN;

GRANT USAGE ON SCHEMA RETAIL_DWH.AUDIT TO ROLE RETAIL_DBT_ROLE;
GRANT SELECT ON TABLE RETAIL_DWH.AUDIT.BRONZE_LOAD_RUNS TO ROLE RETAIL_DBT_ROLE;

SHOW GRANTS TO ROLE RETAIL_DBT_ROLE;
