# RetailFlow dbt project

dbt transformations for RetailFlow. Python ingestion lands BigQuery, API and file data in `RETAIL_DWH.BRONZE.SOURCE_RECORDS`. dbt runs in Snowflake and builds the layers:

- `models/staging`: one typed view per source entity (tag `staging`)
- `models/silver`: current entities, dispositions and SCD history (tag `silver`)
- `models/data_quality`: rule results and quarantine (tag `data_quality`)
- `models/gold`: star schema and KPI marts (tag `gold`)
- `models/reconciliation`: source-to-target checks and the gate test (tag `reconciliation`)
- `models/monitoring`: file feed health and open file issues (tag `monitoring`)
- `macros/generate_schema_name.sql`: keeps layer schemas fixed (no developer prefix)

This folder is a subdirectory of the RetailFlow monorepo. In dbt Cloud, set the project subdirectory to `dbt_retailflow`.

Full build in dbt Cloud Studio:

```
dbt build --select tag:staging tag:silver tag:data_quality tag:gold tag:reconciliation tag:monitoring
```

For local runs, copy `profiles.yml.example` to `profiles.yml` and set the `RETAILFLOW_SF_*` environment variables. Never commit `profiles.yml`.
