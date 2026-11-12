# Phase 0 environment runbook

## Objective

Confirm which source generation path the account can run, whether Snowflake is available, and which local tools are ready. The checks below use existing accounts and objects.

## Local PowerShell

Run the diagnostic from the README. This workspace initially contained no project files or Git metadata. The diagnostic found PowerShell 7.6.5, Git 2.56.0.windows.4, uv 0.13.7 and CPython 3.13.8. The Windows Store alias for plain python failed. gcloud, bq, snow, dbt and code were absent from PATH. Browser-based setup can proceed independently of those CLI commands. To confirm the existing interpreter runs, use:

```powershell
uv --no-cache python find --offline --no-python-downloads 3.13
& (uv --no-cache python find --offline --no-python-downloads 3.13) --version
```

An absent CLI may be installed outside PATH. Use Get-Command after reopening the shell following installation. Resolve Python and package compatibility when pinning the first Python dependencies.

## BigQuery console

Open BigQuery Studio in the existing project. Record its project ID locally, note whether a Sandbox banner appears, and confirm billing mode in the project billing view if you have access. Inspect the location of an existing fixture dataset if one is available. Proposed default for a new dedicated synthetic dataset is US, subject to account policy.

Paste this into the BigQuery SQL editor and check the validator. Running it should return one row containing 1.

```sql
SELECT 1 AS connection_ok;
```

This tests query submission without scanning a source table. A jobs.create denial indicates the query project lacks a grant for your principal. A dataset location error in later phases means the job and referenced datasets need a matching location. Sandbox supports the CTAS fixture path and lacks DML. Use deterministic per-batch CTAS tables and reproducible clean-state views there. A billing-enabled project can also demonstrate INSERT and MERGE when approved. Sandbox grants 10 GiB lifetime storage, 1 TiB of processed query data per month, and automatic 60-day expiration. Track cumulative fixture storage before regenerating batches. In billing-enabled projects use dry runs, explicit projections, partition filters and maximum bytes billed. [Sandbox](https://docs.cloud.google.com/bigquery/docs/sandbox) · [Cost controls](https://docs.cloud.google.com/bigquery/docs/best-practices-costs)

For later Python extraction, install Google Cloud CLI and run the following in local PowerShell. It opens a browser to configure local ADC. Keep the credential file outside this workspace.

```powershell
gcloud auth application-default login
```

A browser console session or regular gcloud login does not establish Python ADC. If a later client reports a quota project or serviceusage.services.use error, check the authorized quota project and grant with the administrator. [BigQuery client authentication](https://docs.cloud.google.com/bigquery/docs/authentication/getting-started)

## Snowflake Snowsight

Confirm you can sign in to the existing account. In a SQL worksheet, run the metadata checks below. Expect a version, account, region and active role. The warehouse list can be empty for a role with limited visibility.

```sql
SELECT CURRENT_VERSION(), CURRENT_ACCOUNT(), CURRENT_REGION(), CURRENT_ROLE();
SHOW WAREHOUSES;
SHOW GRANTS TO USER;
```

If a command is denied, inspect the current role and ask the account administrator to verify its grants. For a safe error-handling demonstration in either SQL editor, validate or run SELECT 1 + ; and observe the syntax error. Then rerun the valid probe. No tables are referenced.

Check trial status and remaining credits in the account interface or with its administrator. The documented trial lasts up to 30 days or until credits are exhausted. Prefer an approved X-Small standard warehouse with roughly 60 seconds of idle auto-suspend for short development bursts. Batch related work because each warehouse start has a 60-second billing minimum. Account-level credit balances and edition remain unverified until you check them. [Trial terms](https://docs.snowflake.com/en/user-guide/admin-trial-account) · [Warehouse billing](https://docs.snowflake.com/en/user-guide/warehouses-overview)

Use the account's interactive login policy for Snowsight. For automation, plan dedicated service users with encrypted PKCS#8 key-pair credentials where supported by policy. Keep keys outside Git and use the connector or dbt credential store for their respective connections. [Snowflake key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth) · [dbt Snowflake connection](https://docs.getdbt.com/docs/platform/connect-data-platform/connect-snowflake)

## dbt platform

In the account UI, verify that the plan is Developer. dbt Labs lists one seat, one project and 3,000 successful models built per month. Snowflake compute is charged separately against its own credits or billing. Use local dbt Core as the CLI for the Python-driven workflow and the hosted Developer project for interactive development when useful. Core uses the dbt-snowflake adapter. Select and pin a tested compatible Core and adapter pair in Phase 7, then verify it with dbt --version and dbt debug against the approved connection. Snowflake also appears as generally available for dbt v2, where adapters ship with the engine. [Developer pricing](https://www.getdbt.com/pricing) · [Supported platforms](https://docs.getdbt.com/docs/supported-data-platforms) · [Adapter releases](https://pypi.org/project/dbt-snowflake/)

## Minimum permissions by job

| Principal | Scope |
| --- | --- |
| BigQuery extraction | BigQuery Job User on the query project and Data Viewer on the source dataset or referenced tables |
| BigQuery fixture writer | Job User on the project and Data Editor on the dedicated fixture dataset. Have an authorized bootstrap principal create the dataset or explicitly grant bigquery.datasets.create for that task |
| Snowflake bootstrap | Authorized role with the necessary create and grant privileges for approved database, schemas and warehouse |
| Snowflake ingestion | Warehouse, database and relevant schema USAGE. SELECT and write privileges required by the Bronze and control/audit load statements. Grant temporary object creation only if the implemented loader requires it |
| Snowflake dbt | Warehouse, database and relevant schema USAGE, SELECT on Bronze and upstream relations, and CREATE TABLE and CREATE VIEW in the target schemas. The dbt deployment role owns its managed relations for rebuilds and incremental writes |
| Analyst | Warehouse, database and Gold schema USAGE and SELECT on approved Gold relations |

Where an approved loader uses a named stage or file format, scope its grants to that object. Production should separate provisioning, load, transformation and reporting identities and use workload identity or rotated credentials. [BigQuery IAM](https://docs.cloud.google.com/iam/docs/roles-permissions/bigquery) · [Snowflake privileges](https://docs.snowflake.com/en/user-guide/security-access-control-privileges)

## Definition of done

The architecture and roadmap are reviewed, the BigQuery mode is known, existing Snowflake access and dbt plan are confirmed, and the local diagnostic runs. Account readiness can be reported as unavailable with the missing capability identified. Record outcomes without credentials or query results that expose private account details.
