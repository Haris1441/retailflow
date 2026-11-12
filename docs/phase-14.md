# Phase 14 · File-driven orchestration, monitoring and recovery

Until Phase 13, a person started every load and named the batch (`--batch BATCH_005`). The batch names and row counts were written in code and in the `source_manifest` seed. Phase 14 adds the way most real data platforms receive data: **the client drops files, the pipeline notices them, works out from the file name what they are, checks them, loads them, and records every step.** No batch name, row count or entity is typed by hand.

```
client ──SFTP──► landing_zone/inbox/ ──sensor (every 15 s)──► match file name against FILE_CONFIG regex
                                                                   │ no match → REJECTED → error/
                                                                   ▼
                                    wait for the .ctl control file (written last by the client)
                                                                   ▼
                       move to processing/ → registry row RECEIVED → checksum + row count vs control file
                                                                   │ mismatch → FAILED → error/
                                                                   ▼
                     same SHA-256 already LOADED? → SKIPPED → archive/   (a redelivery adds nothing)
                                                                   ▼
               existing Bronze MERGE + audit row (one transaction) → registry LOADED + run_id → archive/
                                                                   ▼
                       dbt build (dbt Cloud API job, optional) → reconciliation step 0 + monitoring
```

## What is dynamic now

| Question | Before | Now |
|---|---|---|
| Which feed is this file? | The operator chose `--entity` | Regex on the file name, from `CONTROL.FILE_CONFIG` |
| Which batch? | `--batch BATCH_00N`, limited to 001–008 | From the file name: `..._20250301T090000_001.jsonl` → `BATCH_20250301T090000` |
| How many rows to expect? | `CHANGE_COUNTS` in Python and the `source_manifest` seed | The client's control file, recorded in `CONTROL.FILE_REGISTRY` |
| When does a load start? | When someone runs it | When a file arrives (`watch`), or one `scan` pass |
| What happened to file X? | Not recorded | One registry row per attempt with status, counts, error and Bronze `run_id` |
| New feed? | Code change | One `FILE_CONFIG` row |

Batch IDs that are timestamps always sort correctly, so the `BATCH_1000` problem disappears.

## The file contract

- **Data file:** `retailco_<entity>_<YYYYMMDDTHHMMSS>_<seq>.jsonl`. Each line is one record in the same envelope as the BigQuery change tables:
  ```json
  {"entity":"customers","source_record_id":"BATCH_20250301T090000:customers:1000:1","business_key":"1000",
   "operation":"UPDATE","effective_at":"2025-03-01T09:00:00Z","source_available_at":"2025-03-01T09:00:00Z",
   "payload":{"customer_id":1000,"loyalty_tier":"SILVER", "...": "..."}}
  ```
- **Control file:** same name ending `.ctl`, written **after** the data file:
  ```json
  {"file_name": "retailco_customers_20250301T090000_001.jsonl", "row_count": 3, "sha256": "..."}
  ```
  The control file solves two problems. A file that is still being uploaded is never read, because the pipeline waits for the `.ctl`. A truncated or altered file is caught, because its checksum or row count no longer match.
- **Feed pattern** (a row in `FILE_CONFIG`, a Python regular expression matched against the whole name):
  ```text
  retailco_customers_(?P<batch_ts>[0-9]{8}T[0-9]{6})_(?P<seq>[0-9]{3})[.]jsonl
  ```
  Every pattern must capture `batch_ts`. A name that matches no pattern, or more than one, is rejected.
- **Source system:** the files come from the retailer's core system, the same system the project models as `BIGQUERY`. The transport (SFTP file instead of a BigQuery query) is recorded in the registry, and the Bronze `run_id` links each record to its file. So Silver, SCD history, Gold and reconciliation take the files in with **no model change**.

## Statuses and folders

| Status | Meaning | File goes to |
|---|---|---|
| `RECEIVED` | Attempt started. Still here after an hour = the process stopped mid-file (`STUCK`) | `processing/` |
| `LOADED` | Validated and merged into Bronze; `RUN_ID` → `AUDIT.BRONZE_LOAD_RUNS` | `archive/<date>/` |
| `SKIPPED` | Same content (SHA-256) already loaded under some name. Nothing loaded | `archive/<date>/` |
| `FAILED` | Bad control file, checksum, row count, line or load error. Nothing loaded | `error/` |
| `REJECTED` | File name matches no enabled feed | `error/` |

Nothing half-loads. The Bronze MERGE and its audit row are one transaction, and any failure before or during it rolls back.

## Recovery runbook

| Situation | What you see | What to do |
|---|---|---|
| Wrong row count or checksum | `FAILED`, file in `error/`, warning in dbt | Ask the client to resend. A new attempt of the same name that loads closes the issue (`simulate --scenario resend` plays the client) |
| Process killed mid-file | Registry `RECEIVED`, file in `processing/`, `STUCK` after an hour | Run `scan` again. It moves the file back and reloads; the MERGE inserts only what is missing |
| Client resends a file already loaded | `SKIPPED` | Nothing. That is the point |
| Unknown file name | `REJECTED`, `REJECTED_NAME` in `mon_open_file_issues` | Agree the name with the client, or add a `FILE_CONFIG` row for a new feed |
| Bronze already holds a different image for the same record ID | `FAILED` with that message | Corrections must come as a new batch (new record IDs), never as an edited old file |
| dbt build fails after a load | Data is safe in Bronze | Fix and rerun the build. Every model rebuilds from Bronze |

## Monitoring

- `DATA_QUALITY.MON_FILE_FEEDS`: one row per feed with files loaded, skipped, failed, open failures, stuck attempts, rows inserted, last load and `freshness_status` (`NO_FILES_YET`, `ON_TIME`, `LATE` against `EXPECTED_EVERY_HOURS`). Freshness uses processing time, not the fixture's 2025 business dates.
- `DATA_QUALITY.MON_OPEN_FILE_ISSUES`: the operator's work list. Empty means nothing to do.
- `tests/assert_no_open_file_failures` (severity **warn**): the build publishes what loaded but shows a warning while a `FAILED` or `STUCK` file is unresolved.
- Reconciliation **step 0** `recon_landing_to_bronze`: every loaded file's control count = rows read = rows its audited Bronze run extracted, and inserted/matched agree. Step 1 now takes expected counts for file batches from the registry, so no manifest edit is needed.

## Run it

**1. Snowflake (once, as ACCOUNTADMIN):** run [file_ingestion.sql](../sql/snowflake/01_control/file_ingestion.sql). It creates `FILE_CONFIG` (15 feeds) and `FILE_REGISTRY`, and grants them to `RETAILFLOW_LOADER` and `RETAIL_DBT_ROLE`.

**2. dbt Cloud:** switch to `phase-14-orchestration` and pull. Run the build once **before** any file lands. Expect it to pass with step 0 at 0 items:
```text
dbt build --select tag:staging tag:silver tag:data_quality tag:gold tag:reconciliation tag:monitoring
```

**3. The demo**, from the project folder in PowerShell. It uses the same `retailflow` connection as Phases 5 and 6:
```powershell
# a) The client delivers three files: 3 customer tier changes, 2 product price changes, 5 new events (2 late)
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password simulate
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password scan
#    expect 3 x LOADED

# b) The client sends the same file again
.\.venv\Scripts\python.exe -m landing simulate --scenario redeliver
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password scan
#    expect SKIPPED  <the most recently archived file>  already loaded as ...

# c) A file nobody configured, and a delivery whose control file is wrong
.\.venv\Scripts\python.exe -m landing simulate --scenario bad-name
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password simulate --scenario bad-count
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password scan
#    expect REJECTED customers_latest_FINAL.jsonl and FAILED retailco_customers_... (promises 4 rows, has 3)

# d) Recovery: the client resends with a correct control file
.\.venv\Scripts\python.exe -m landing simulate --scenario resend
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password scan
#    expect LOADED, 3 rows

.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password status
```
To see the event-driven version, run `watch` in one terminal and the `simulate` commands in another. Each file is processed within 15 seconds of landing:
```powershell
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password watch
```

**4. dbt Cloud:** run the same build again, as a normal run with no `--full-refresh`. Payments and events stay incremental and pick up the new events by arrival time. The warn test should pass, because the failed file was resent.

**5. Snowsight:** run [landing.sql](../sql/snowflake/05_validation/landing.sql) and compare with the expected values in its comments.

### Optional: let the pipeline start dbt

Create a dbt Cloud deploy job running the build above. Then set the following in the shell and add `--trigger-dbt` to `scan` or `watch`:
```powershell
$env:DBT_CLOUD_HOST = 'https://<your access URL>'   # dbt Cloud: Account settings > Access URLs
$env:DBT_CLOUD_ACCOUNT_ID = '<account id>'
$env:DBT_CLOUD_JOB_ID = '<job id>'
$env:DBT_CLOUD_API_TOKEN = Read-Host 'dbt Cloud token'   # session only, never in a file
```
After a scan that loaded anything, the pipeline starts the job and waits for `SUCCESS` or `ERROR`. API job triggers depend on the dbt Cloud plan. Without them the pipeline prints that a build is due.

## What changes downstream

The new batches are real new data. After step 4, customer tiers, product prices and event counts differ from the Phase 11 and 12 expected values. The earlier state is still reproducible: file batch IDs sort after `BATCH_008`, so `--vars '{cdc_through_batch: BATCH_008}'` (with `--full-refresh` on the two incremental models) rebuilds exactly the Phase 13 state.

## The same design in production, for example Azure Data Factory

| This repo (local) | Production equivalent |
|---|---|
| `landing_zone/inbox/` | SFTP server, or Azure Blob/ADLS or S3 landing container |
| `watch` sensor polling every 15 s | Storage event trigger (Event Grid / S3 notification), or an Airflow/Dagster sensor |
| `FILE_CONFIG` regex, matched in Python | Same table. ADF triggers filter only on prefix and suffix, so the full regex runs in a Lookup + `REGEXP_LIKE` or a small Function |
| `processing/`, `archive/`, `error/` moves | ADF Copy + Delete activities |
| Python reads JSONL into the Bronze MERGE | ADF Copy into a raw table, then the same MERGE from a Script activity or stored procedure |
| `FILE_REGISTRY` | Same table, written by Script activities on success and failure paths |
| `--trigger-dbt` | Web activity calling the dbt Cloud job API, plus an Until loop on run status |
| Warn test + `mon_open_file_issues` | Same models, wired to email or Teams alerts |

dbt does not change between the two. It still only transforms what is already in Snowflake.

## Files

| Path | Purpose |
|---|---|
| [file_ingestion.sql](../sql/snowflake/01_control/file_ingestion.sql) | `FILE_CONFIG` with 15 feed patterns, `FILE_REGISTRY`, grants |
| `landing/files.py` | Regex matching, control file checks, JSONL envelope → Bronze records |
| `landing/processor.py` | Folders, one attempt per file, statuses, recovery of interrupted files |
| `landing/registry.py` | Reads feeds and writes registry rows in Snowflake |
| `landing/simulator.py` | Plays the client: builds deliveries from existing records |
| `landing/dbt_cloud.py` | Optional dbt Cloud job trigger and wait |
| `landing/__main__.py` | `simulate`, `scan`, `watch`, `status` |
| `tests/unit/test_landing.py` | 12 tests: regex, waiting, rejection, row count, checksum, skip, load failure, bad line, recovery |
| `dbt_retailflow/models/reconciliation/recon_landing_to_bronze.sql` | Reconciliation step 0 |
| `dbt_retailflow/models/monitoring/` | `mon_file_feeds`, `mon_open_file_issues` |
| `dbt_retailflow/tests/assert_no_open_file_failures.sql` | Warn-level alert |
| [landing.sql](../sql/snowflake/05_validation/landing.sql) | Evidence queries with expected values |

## Definition of done

The unit tests pass. The build passes before any file arrives (step 0 has 0 items). The demo produces 4 LOADED, 1 REJECTED and 1 FAILED attempts, plus one SKIPPED per redelivery, with 13 rows inserted. After the second build, all 7 reconciliation checks pass, the new customer, product and event versions are current in Silver with history, and the only open issue is the rejected file name.

## Outcome (2026-11-12)

Run locally against Snowflake, then rebuilt in dbt Cloud on `main` with no errors and no warnings.

| Check | Result |
|---|---|
| Feeds | 15 configured, 15 enabled |
| Attempts | 4 LOADED (13 rows inserted), 2 SKIPPED redeliveries of the products file, 1 REJECTED (`customers_latest_FINAL.jsonl`), 1 FAILED (control file promised 4 rows, file had 3), then LOADED after the resend |
| Lineage | All 4 loaded files point to an audited Bronze run with equal counts |
| Bronze | `BATCH_20250301T090000`: customer_events 5, customers 3, products 2. `BATCH_20250302T090000`: customers 3 |
| Silver | 6 customers, 2 products and 5 events from files are current. Events 14400 and 14401 arrived 21 days after they happened and were still picked up by the incremental model |
| History | Customers 1000 to 1005 each have 2 Type 2 versions split at the delivery time, and a Type 3 previous tier |
| Reconciliation | 7 of 7 PASS. Step 0 covers 4 files. Step 1 covers 52 batch rows (48 manifest + 4 from control files). Step 2 covers 17 audited runs (13 + 4) |
| Monitoring | All three active feeds ON_TIME and OK. Customers shows 1 failed attempt and 0 open failures. The only open issue is the rejected file name |

The Azure Data Factory version (`azure/`, `sql/snowflake/01_control/azure_landing.sql`) was written but not deployed: the Azure account has no subscription and pay-as-you-go was declined. The design maps one to one (see the production table above).
