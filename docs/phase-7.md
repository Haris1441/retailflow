# Phase 7 · dbt project and staging models

dbt begins after Python has landed raw evidence in Bronze. It connects directly to Snowflake, declares `BRONZE.SOURCE_RECORDS` as a dbt source, and creates STAGING views in the same warehouse. dbt does not read BigQuery or call the mock API. The data movement boundary remains the ingestion framework from Phases 5 and 6.

The project contains one staging model per BigQuery and API entity. Each row remains one Bronze delivery, identified by `source_record_id`. Core models cast source attributes using Snowflake `TRY_` functions so malformed values become null for later quality classification instead of failing a whole dbt run. Raw JSON remains available in every model. Staging normalizes strings and exposes nested API order arrays without flattening them. Phase 8 will resolve records, flatten arrays, deduplicate, and build trusted Silver entities.

The project overrides dbt's default development-schema naming so a model configured with `schema: STAGING` builds exactly in `RETAIL_DWH.STAGING`. Without that override, dbt Cloud commonly prefixes the configured schema with the development schema, such as `DBT_HARIS_STAGING`. This is intentional for the shared learning environment. A production project would preserve isolated developer schemas and deploy the shared STAGING layer only through controlled jobs.

## 1. Grant a transformation role

Run [grant_dbt.sql](../sql/snowflake/00_setup/grant_dbt.sql) in Snowsight using an authorized administrative role. Edit and run its final user grant for your intended dbt identity. The role can read Bronze and create relations only in STAGING. It cannot write Bronze.

## 2. Run locally

From the repository root, install the adapter into the existing virtual environment.

```powershell
uv --no-cache pip install --python .venv/Scripts/python.exe -r dbt_retailflow/requirements.txt
```

Create `dbt_retailflow/profiles.yml` by copying `profiles.yml.example`. The file is ignored by Git. Set environment variables instead of committing credentials. This example matches your existing password-prompt authentication. `dbt` does not offer an interactive password prompt, so set the password only in the active PowerShell process.

```powershell
Copy-Item .\dbt_retailflow\profiles.yml.example .\dbt_retailflow\profiles.yml
$env:RETAILFLOW_SF_ACCOUNT = 'your-organization-your-account'
$env:RETAILFLOW_SF_USER = 'your-snowflake-user'
$securePassword = Read-Host 'Snowflake password' -AsSecureString
$env:RETAILFLOW_SF_PASSWORD = [System.Net.NetworkCredential]::new('', $securePassword).Password
$env:RETAILFLOW_SF_ROLE = 'RETAIL_DBT_ROLE'
$env:RETAILFLOW_SF_WAREHOUSE = 'RETAILFLOW_WH'
$env:RETAILFLOW_SF_DATABASE = 'RETAIL_DWH'
$env:RETAILFLOW_SF_AUTHENTICATOR = 'username_password_mfa'

Set-Location .\dbt_retailflow
..\.venv\Scripts\dbt.exe debug
..\.venv\Scripts\dbt.exe parse
..\.venv\Scripts\dbt.exe build --select tag:staging
```

The `Read-Host` command leaves the password only in the current PowerShell session. Close that shell or remove `$env:RETAILFLOW_SF_PASSWORD` when finished. If your account requires MFA, configure dbt Cloud with the approved account authentication method, or use a separate approved service user for dbt automation. Do not add the password to `profiles.yml`.

The project pins matching dbt-core and dbt-snowflake 1.11.6. The current dbt-core 1.12 line adds an experimental parser that downloads a separate Windows wheel from GitHub during installation. That step can fail on a machine whose TLS-inspection certificate is not available to Python. dbt Cloud Studio remains an alternative because it provides the managed runtime.

## 3. Run in dbt Cloud Studio

Create a project from this repository and configure a Snowflake connection targeting `RETAIL_DWH`, `RETAILFLOW_WH`, and `RETAIL_DBT_ROLE`. In Studio, run:

```text
dbt build --select tag:staging
```

dbt Developer supports one project and one developer seat. Configure a separate source freshness job or command because `dbt build` does not execute source freshness checks. Snowflake source freshness based on object metadata can be affected by non-data object changes. The Bronze ingestion audit and CONTROL watermarks remain the operational freshness source for this project. [dbt sources](https://docs.getdbt.com/docs/build/sources) · [source freshness](https://docs.getdbt.com/docs/deploy/source-freshness)

## Validation

After `dbt build`, run these in Snowsight. The first returns 5,025 customer delivery images. It includes the 5,000 baseline rows and 25 later customer changes. The second confirms each selected model row comes from a Bronze identity.

```sql
SELECT COUNT(*) AS staged_customer_deliveries
FROM RETAIL_DWH.STAGING.STG_BQ_CUSTOMERS;

SELECT COUNT(*) AS missing_bronze_identity
FROM RETAIL_DWH.STAGING.STG_BQ_ORDERS AS staged
LEFT JOIN RETAIL_DWH.BRONZE.SOURCE_RECORDS AS bronze
  ON staged.source_record_id = bronze.source_record_id
 AND bronze.source_system = 'BIGQUERY'
 AND bronze.entity = 'orders'
WHERE bronze.source_record_id IS NULL;
```

Expected `missing_bronze_identity` is zero. Staging row counts intentionally include updates and duplicates because Bronze preserves source delivery history.

## Definition of done

`dbt debug`, `dbt parse`, and `dbt build --select tag:staging` succeed, STAGING views exist, generic source and model tests pass, and the lineage validation returns zero missing identities. Phase 8 will add trusted Silver models and data quality decisions.

## Outcome

Phase 7 runs in dbt Cloud from the GitHub repository `Haris1441/retailflow` on branch `phase-7-staging`. At the time the dbt project sat at the repository root, so the dbt Cloud project subdirectory was blank. Since the monorepo change (2026-11-12) the whole platform lives in the repository and the dbt project is in `dbt_retailflow/`, so the project subdirectory is `dbt_retailflow`. The dbt Cloud connection uses role `RETAIL_DBT_ROLE`. `dbt build --select tag:staging` built 20 views and passed 15 tests. Validation returned 5,025 staged customer deliveries and zero missing Bronze identities.
