# RetailFlow dbt project

dbt transformations for RetailFlow. Python ingestion lands BigQuery and API data in `RETAIL_DWH.BRONZE.SOURCE_RECORDS`. dbt runs in Snowflake and builds layered models.

- `models/staging`: one typed view per source entity, built in `RETAIL_DWH.STAGING` (tag `staging`)
- `macros/generate_schema_name.sql`: keeps layer schemas fixed (no developer prefix)

Run in dbt Cloud Studio:

```
dbt build --select tag:staging
```

For local runs, copy `profiles.yml.example` to `profiles.yml` and set the `RETAILFLOW_SF_*` environment variables. Never commit `profiles.yml`.
