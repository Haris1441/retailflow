# Phase 5 · Snowflake Bronze ingestion

Bronze keeps the physical source record, its business key, provenance and original JSON payload. A BigQuery event deliberately duplicated in Phase 3 has a different physical record ID and lands as additional evidence. An API boundary repeat has the same key and update timestamp and lands once. The API fixture assumes that a business record can have only one payload at each update timestamp. Conflicting images fail reconciliation and require a stronger source identity.

One shared SOURCE_RECORDS table gives the loader a single landing contract across the 15 BigQuery entities, seven change batches and five API collections. Snowflake VARIANT preserves the nested payload. Currency strings and numeric encodings follow the source. The record hash covers the payload and stable metadata, excludes extraction timestamps and sorts object keys without converting exact decimals to binary floats.

The loader stages bounded chunks in a session-temporary table, verifies extraction counts, checks for conflicting images, and inserts unseen identities with MERGE. The audit row and Bronze changes commit together. A failed read or load rolls back. The reconciliation counts describe this run's selected identities. An API duplicate scenario can extract 50 deliveries for 40 distinct identities. Baseline defects and source duplicates remain in Bronze for downstream validation.

## 1. Review and run the Snowflake setup

In **Snowsight**, open a worksheet and select a role authorized to create the approved database and warehouse. Run [bootstrap.sql](../sql/snowflake/00_setup/bootstrap.sql) after reviewing the names. It creates RETAIL_DWH with seven schemas, the Bronze and audit tables, and a suspended X-Small RETAILFLOW_WH with 60-second auto-suspend and a 300-second statement timeout. Loading resumes the warehouse and can consume trial credits. If using an approved existing warehouse, omit the warehouse creation statement and use its name in the client profile. IF NOT EXISTS retains existing objects and settings.

For a dedicated loader role, an authorized administrator can run [grant_loader.sql](../sql/snowflake/00_setup/grant_loader.sql). The administrator must also grant RETAILFLOW_LOADER to the intended Snowflake user, substituting that user's actual identifier in Snowsight.

```sql
GRANT ROLE RETAILFLOW_LOADER TO USER YOUR_SNOWFLAKE_USER;
```

Use an approved loader role in the client profile. Session-temporary tables do not require the schema CREATE TABLE privilege. Bootstrap and grant files use the default object names. If changing the database, use the same name in SQL, the profile and RETAILFLOW_SF_DATABASE. [Snowflake temporary tables](https://docs.snowflake.com/en/user-guide/tables-temp-transient)

## 2. Configure local authentication

From the repository root in **PowerShell**, install the ingestion requirements into the Phase 4 virtual environment if needed.

```powershell
uv --no-cache pip install --python .venv/Scripts/python.exe -r ingestion/requirements.txt
```

If PowerShell reports that gcloud is not recognized, install the Google Cloud CLI from the [official Windows instructions](https://docs.cloud.google.com/sdk/docs/install-sdk#windows). Keep the option to add gcloud to PATH, then close and reopen PowerShell. Run gcloud --version before continuing. If PowerShell blocks gcloud.ps1, use gcloud.cmd --version and gcloud.cmd auth application-default login. This uses the SDK batch launcher with the existing PowerShell execution policy. Run the following locally and complete the browser flow using the Google account that can query your Sandbox dataset. The Google identity needs BigQuery Job User on the query project and Data Viewer on the fixture dataset. The query location must match the dataset.

```powershell
gcloud auth application-default login
$env:RETAILFLOW_BQ_PROJECT = 'your-sandbox-project-id'
$env:RETAILFLOW_BQ_DATASET = 'retailflow_source'
$env:RETAILFLOW_BQ_LOCATION = 'US'
```

For Snowflake, create a named connection outside the repo. The Windows connector looks in %USERPROFILE%\.snowflake\connections.toml when that directory exists, otherwise in %LOCALAPPDATA%\snowflake\connections.toml, unless SNOWFLAKE_HOME overrides it. Example for a user whose account supports browser-based SSO:

```toml
[retailflow]
account = "organization-account"
user = "YOUR_SNOWFLAKE_USER"
authenticator = "externalbrowser"
role = "RETAILFLOW_LOADER"
warehouse = "RETAILFLOW_WH"
```

If the account uses key-pair authentication, use the approved named connection with authenticator SNOWFLAKE_JWT and its local private key configuration. Keep keys and passphrases out of Git and chat. Snowsight access and connector authentication are separate checks. The loader defaults to the retailflow profile and RETAIL_DWH. The environment example lists overrides. [BigQuery ADC](https://docs.cloud.google.com/bigquery/docs/authentication/getting-started) · [Snowflake connector profiles and authentication](https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-connect)

If the loader reports Invalid connection_name 'retailflow', known ones are [], ask the installed connector for its exact path and open that file from the repository root in PowerShell.

```powershell
$profilePath = & .\.venv\Scripts\python.exe -c "from snowflake.connector.constants import CONNECTIONS_FILE; print(CONNECTIONS_FILE)"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profilePath) | Out-Null
notepad.exe "$profilePath"
```

Save the connection example above using the actual account, username, approved role, warehouse and authentication method. In Notepad use the filename connections.toml and the All files type if prompted. Verify the section name without printing any credentials.

```powershell
.\.venv\Scripts\python.exe -c "import tomllib; from snowflake.connector.constants import CONNECTIONS_FILE; print('retailflow profile found:', 'retailflow' in tomllib.loads(CONNECTIONS_FILE.read_text(encoding='utf-8')))"
```

If the profile is found but the connector reports Password is empty, it is attempting password authentication without a password. For a Snowflake password and MFA login, add authenticator = "username_password_mfa" to the retailflow profile and append --prompt-snowflake-password to each load command. Approve the MFA push if your account uses one. For an enrolled authenticator app that requires a code, also append --prompt-snowflake-passcode. The loader reads both values without echoing them. If your organization uses browser SSO, configure externalbrowser and use the load commands as written below. [Snowflake MFA connector options](https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-connect)

## 3. Run the loads and replay

Run the commands one at a time from the repository root in **PowerShell**. Start with customers to verify both cloud connections at small scope. The full baseline will match those previously loaded customers and insert the remaining rows. Start the mock server in a separate terminal using the [Phase 4 runbook](phase-4.md) before running the API command.

```powershell
.\.venv\Scripts\python.exe -m ingestion bigquery --entity customers
.\.venv\Scripts\python.exe -m ingestion bigquery
foreach ($batchNumber in 2..8) {
    $batchName = 'BATCH_{0:000}' -f $batchNumber
    .\.venv\Scripts\python.exe -m ingestion bigquery --batch $batchName
    if ($LASTEXITCODE -ne 0) { throw "Failed $batchName" }
}

$env:RETAILFLOW_API_TOKEN = 'retailflow-local-demo'
.\.venv\Scripts\python.exe -m ingestion api --scenario duplicate
.\.venv\Scripts\python.exe -m ingestion api --scenario duplicate
```

| Scope | Extracted | Distinct | Inserted on clean target |
| --- | ---: | ---: | ---: |
| Customers smoke | 5,000 | 5,000 | 5,000 |
| BigQuery baseline after customers smoke | 119,937 | 119,937 | 114,937 |
| BigQuery changes, total across seven runs | 7,678 | 7,678 | 7,678 |
| API duplicate scenario | 50 | 40 | 40 |
| API replay | 50 | 40 | 0 |

Run [bronze.sql](../sql/snowflake/05_validation/bronze.sql) in Snowsight with a warehouse and role that can read Bronze and Audit. Expect **127,655** Bronze rows across the fully loaded sources and no duplicate physical identities. The replay audit row should show 40 matches and zero inserts. An independent baseline rerun should show zero inserts and 119,937 matches.

## Failure handling and limits

For an API failure demonstration, stop the mock server and rerun the API load. Expect a connection error after the bounded retries, no committed Bronze rows for that attempt and no success audit row. Restart the server and replay. For BigQuery access errors, check ADC, job-project permission, dataset permission and the configured location. For a manifest count failure, rerun the corresponding Phase 2 or Phase 3 validator before loading. A Snowflake 403, missing connection or unauthorized object error requires checking the profile, account policy, warehouse and role grants.

The local loader uses a default 1 GiB cap per BigQuery query job. Smaller Snowflake chunks can help if request sizes grow. Run only one Bronze writer at a time. Snowflake standard table primary keys are informational, so this implementation relies on the single-writer operating rule plus deterministic MERGE and reconciliation. Production would use bulk staging and COPY, durable failure audit, protected workload credentials and a scheduler that enforces one writer or a coordinated concurrency design. Phase 6 introduces configured watermarks. [BigQuery query cost controls](https://docs.cloud.google.com/bigquery/docs/best-practices-costs) · [Snowflake MERGE](https://docs.snowflake.com/en/sql-reference/sql/merge)

## Definition of done

The setup runs, both connectors authenticate, the baseline and all seven change batches and API fixtures load, the validation query returns zero duplicate physical keys, and the replay inserts zero rows. Local tests cover loader transaction branches. Authenticated cloud execution must verify the SQL and permissions.
