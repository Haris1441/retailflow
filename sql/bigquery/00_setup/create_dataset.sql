-- Run once in the selected BigQuery project with processing location US.
CREATE SCHEMA IF NOT EXISTS `retailflow_source`
OPTIONS (location = 'US', description = 'Dedicated synthetic RetailFlow source fixtures');
