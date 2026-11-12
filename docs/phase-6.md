# Phase 6 · Metadata-driven ingestion and watermarks

Phase 5 proved that fixed fixture batches can land safely. This phase makes a source entity's extraction policy data-driven. Snowflake CONTROL tables define the watermark field, overlap duration, maximum permitted backfill, enabled state, the prior successful watermark, and pipeline run status.

An incremental run starts from `last_successful_watermark - overlap_minutes`. It intentionally re-reads the overlap to protect against an update at the boundary. Bronze physical identity makes the re-read idempotent. A successful Bronze load commits before the control transaction advances the watermark. If updating CONTROL fails afterward, the next run repeats data safely and does not lose it. If extraction or Bronze loading fails, the control run becomes `FAILED` and its old watermark remains in place.

The Phase 6 CLI initially activates this policy for the local API because it has a stable `updated_at` field and an observable late update. BigQuery batch fixtures use immutable availability timestamps and are already fully loaded. The same control contract will govern BigQuery incremental discovery when Phase 10 adds batch selection and replay.

## 1. Create metadata controls

In Snowsight, select `RETAIL_DWH` and run [metadata.sql](../sql/snowflake/01_control/metadata.sql). It creates only CONTROL tables and seeds 11 entity configurations. It does not reload source data, change Bronze, or reset existing checkpoints.

Then run [control.sql](../sql/snowflake/05_validation/control.sql). Before the first metadata-run, watermark columns are null.

## 2. Demonstrate a bounded API incremental run

Start the mock API in one PowerShell window using the [Phase 4 runbook](phase-4.md). In a second window, use the existing environment values and run one entity at a time.

```powershell
$env:RETAILFLOW_API_TOKEN = 'retailflow-local-demo'
.\.venv\Scripts\python.exe -m pipeline run --entity orders --prompt-snowflake-password
.\.venv\Scripts\python.exe -m pipeline status --entity orders --prompt-snowflake-password
```

Expected first result is `extracted=8`, `inserted=0`, and `matched=8`. The API order records were already loaded in Phase 5, so this validates the control flow without adding another physical copy. The status command should show the `2025-01-15` update watermark for orders.

Run the same command again. The one-hour overlap selects the API order updated at the stored boundary. Expect `extracted=1`, `inserted=0`, and `matched=1`. This demonstrates a safe replay at the boundary.

## 3. Validate control state

Run [control.sql](../sql/snowflake/05_validation/control.sql) again. Expect one `SUCCEEDED` order run per command. The order watermark should remain at the latest observed update time after the second run. The Bronze table remains at `127,655` total records.

To demonstrate failure handling, stop the API server and run the command once. Expect a failed CLI request and a `FAILED` control run. The order watermark must remain unchanged. Restart the API and rerun. The repeated source records match Bronze and advance no further than the source's latest update.

## Common issues

If CONTROL access is denied, grant the loader role USAGE on the CONTROL schema and SELECT, INSERT, UPDATE on CONTROL.ENTITY_CONFIG, CONTROL.WATERMARKS, and CONTROL.PIPELINE_RUNS. If a connection cannot authenticate, use the established `--prompt-snowflake-password` option. If the API call fails, ensure the Uvicorn process remains running on `127.0.0.1:8000` and the token matches in both shells.

Polling a mutable API cannot recover versions changed and overwritten between polls or an unobserved hard delete. A source change feed or tombstone is required for that completeness guarantee. The 45-day backfill setting is a control limit to be used by the later BigQuery change selector, not an automatic claim that polling detects every older update.

## Definition of done

Metadata SQL runs, the two API incremental runs produce the expected match-only results, the second run proves overlap behavior, and CONTROL shows successful run and watermark state. Local tests verify metadata retrieval, overlap computation, transaction behavior, and failure rollback.
