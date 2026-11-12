-- Fivetran destination access for RetailFlow.
-- Run once in Snowsight with ACCOUNTADMIN (or a role that can create roles and users
-- and owns RETAIL_DWH) BEFORE adding Snowflake as a destination in Fivetran.
--
-- Fivetran gets its own role and SERVICE user. It may create its own schemas in
-- RETAIL_DWH, but it cannot read or write BRONZE, STAGING, CONTROL or any other
-- existing schema.

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS FIVETRAN_ROLE;

-- Paste the public key body (the text between the BEGIN/END lines of
-- fivetran_rsa_key.pub, without line breaks) in place of the placeholder.
-- Never paste the private key here.
CREATE USER IF NOT EXISTS FIVETRAN_USER
  TYPE = SERVICE
  DEFAULT_ROLE = FIVETRAN_ROLE
  DEFAULT_WAREHOUSE = RETAILFLOW_WH
  RSA_PUBLIC_KEY = 'PASTE_PUBLIC_KEY_BODY_HERE'
  COMMENT = 'Fivetran destination user for the RetailFlow build-vs-buy comparison';

GRANT ROLE FIVETRAN_ROLE TO USER FIVETRAN_USER;
GRANT ROLE FIVETRAN_ROLE TO ROLE SYSADMIN;

-- Shares the existing X-Small warehouse (60-second auto-suspend).
GRANT USAGE ON WAREHOUSE RETAILFLOW_WH TO ROLE FIVETRAN_ROLE;

-- Fivetran creates and owns the schema for each connection
-- (for example FIVETRAN_BQQ_RETAILFLOW_SOURCE).
GRANT USAGE ON DATABASE RETAIL_DWH TO ROLE FIVETRAN_ROLE;
GRANT CREATE SCHEMA ON DATABASE RETAIL_DWH TO ROLE FIVETRAN_ROLE;

-- Checks
SHOW GRANTS TO ROLE FIVETRAN_ROLE;
DESC USER FIVETRAN_USER;
