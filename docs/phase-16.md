# Phase 16 · Final operational demonstration, portfolio and interview walkthrough

Phases 0 to 15 built the platform piece by piece. Phase 16 shows it working as one system, live, in about 20 minutes: **a client delivers files, the pipeline identifies, checks and loads them, dbt Cloud rebuilds production, and the evidence queries follow one delivery from the file to the KPI layer, with reconciliation and monitoring proving nothing was lost.** It also packages the project for a portfolio and an interview.

| Deliverable | Where |
|---|---|
| Live demo runbook | This document |
| Demo evidence queries | [demo.sql](../sql/snowflake/05_validation/demo.sql) |
| Interview walkthrough | [interview-guide.md](interview-guide.md) |
| Portfolio front page | [README](../README.md) |
| Documentation site | https://haris1441.github.io/retailflow/ |

## Before the demo (10 minutes, the day before)

| Check | How | Expect |
|---|---|---|
| Local environment | `.\.venv\Scripts\python.exe -m pytest tests\unit api\tests -q` | 38 passed |
| Snowflake login | `.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password status` | The latest registry rows, no error |
| Empty inbox | `Get-ChildItem landing_zone\inbox` | Nothing, or no folder yet |
| Production is green | dbt Cloud → Orchestration → Runs | Last `prod_build` run Success |
| Open issues are known | Query 8 in `demo.sql` | Only the misnamed files from earlier demos |
| CI evidence | GitHub → Pull requests → Closed → #17 | Three green checks |
| Docs site | https://haris1441.github.io/retailflow/ | Opens, lineage graph works |

Keep these tabs open: the GitHub repository, PR #17, the docs site lineage graph, dbt Cloud Runs, and Snowsight with `demo.sql`. Open PowerShell in the repository root.

## The demo

### Act 1 · The problem and the shape (2 minutes)

Open the README diagram. Say what the business needs (trusted sales, returns, inventory and customer KPIs from two sources) and the rule the platform follows: **every record is accounted for, from the source file to the KPI, and the build fails if one goes missing.**

### Act 2 · How a change gets to production (3 minutes)

Open PR #17 on GitHub. Three checks: Python tests and dbt parse and compile in GitHub Actions (seconds, no warehouse), then dbt Cloud building only the changed model in its own `DBT_CLOUD_PR_…` schema. Open **Settings → Rules** to show `protect_main`: nothing reaches `main` without the three checks. Open the docs site and click through the lineage from a Bronze source to `gold_monthly_revenue`.

### Act 3 · A client delivery, live (5 minutes)

```powershell
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password simulate
```

It prints three file names and the batch, for example `BATCH_20250304T090000`. **Write the batch down** and set it at the top of `demo.sql`. Show the inbox: three `.jsonl` files and three `.ctl` control files.

```powershell
Get-ChildItem landing_zone\inbox
Get-Content (Get-ChildItem landing_zone\inbox\*.ctl | Select-Object -First 1)
```

Talking point: the client writes the control file last, with the row count and SHA-256, so a half-uploaded file is never read.

```powershell
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password scan
```

Expect three `LOADED` lines and "New data in Bronze. Run the dbt build". The files move to `archive\<date>\`.

### Act 4 · Things going wrong (3 minutes)

```powershell
.\.venv\Scripts\python.exe -m landing simulate --scenario bad-name
.\.venv\Scripts\python.exe -m landing simulate --scenario redeliver
.\.venv\Scripts\python.exe -m landing --prompt-snowflake-password scan
```

Expect `REJECTED customers_latest_FINAL.jsonl` (the name matches no feed) and `SKIPPED` for the redelivered file (same SHA-256 as a file already loaded). The rejected file is parked with a time suffix if an earlier copy is already in `error\`. Nothing is loaded twice, and the bad file is parked in `error\` with a reason in the registry.

### Act 5 · Production rebuild (3 to 5 minutes)

In dbt Cloud: **Orchestration → Jobs → prod_build → Run now**. While it runs, explain the layers: staging, Silver dispositions, data quality and quarantine, SCD history, Gold star schema, reconciliation, monitoring. On the free Developer plan the job is started by hand; with API access, `scan --trigger-dbt` starts it when files load.

Expect: Success, every model and test passing, no warnings. A misnamed file is listed in monitoring but does not raise the `assert_no_open_file_failures` warning; only a FAILED or stuck file does.

### Act 6 · Follow the delivery (5 minutes)

Run [demo.sql](../sql/snowflake/05_validation/demo.sql) one query at a time:

| Query | What it proves |
|---|---|
| 1 Files | Each decision with its evidence: rows promised, rows read, rows inserted, checksum |
| 2 Lineage | Every loaded file points to one audited Bronze run with equal counts |
| 3 Silver | The changes are now current: 3 customers, 2 products, 5 events |
| 4 Late arrivals | Two events 21 days late were still picked up by the incremental model |
| 5 History | New Type 2 versions start at the delivery time; old versions are closed, not overwritten; price + 5 |
| 6 Gold | Past orders keep the tier in force when they were placed; the current row shows the new tier |
| 7 Reconciliation | All 7 checks PASS, and step 0 now includes the demo files with no manifest edit |
| 8 Monitoring | Feeds ON_TIME and OK; the only open issue is the misnamed file name (one row per name) |

Close with cost: the whole platform ran on about 6 Snowflake credits in its first 10 days, with auto-suspend and a 20-credit monthly cap.

## If something goes wrong during the demo

| Symptom | Cause | Fix |
|---|---|---|
| `simulate` or `scan` asks nothing and fails to log in | Password prompt flag missing | Add `--prompt-snowflake-password` before the command |
| `WAITING` instead of `LOADED` | The control file is not there yet | Run `scan` again; only a client writes `.ctl` |
| A file stays in `processing\` after a crash | The run was interrupted | Run `scan`; it moves interrupted files back to the inbox and processes them again (the MERGE adds only missing rows) |
| dbt Cloud run fails on reconciliation | A layer lost or duplicated rows | Read `DATA_QUALITY.RECON_SUMMARY`; the failing step names the layer |
| Warehouse suspended by the resource monitor | Monthly cap reached | Snowsight → Admin → Cost management; raise the quota or wait for the month to reset |

## After the demo

The demo adds one real delivery. That is safe to keep: every later demo picks the next unchanged records and the next day (`simulate` reads Bronze), and reconciliation counts from the registry, not a hand-kept list. The misnamed file stays an open issue until removed from `landing_zone\error\` and its registry row resolved; leaving it shows monitoring at work.

## Definition of done

The demo runs end to end without manual fixes: 3 files LOADED, 1 REJECTED, 1 SKIPPED, `prod_build` green, every `demo.sql` check as expected, all reconciliation checks PASS. The interview guide and the README tell the story without the presenter.

## Outcome (2026-11-20, rehearsal)

Run end to end in about 15 minutes with no manual fixes.

| Step | Result |
|---|---|
| Pre-flight | 38 Python tests passed; Snowflake login OK; inbox and processing empty; last `prod_build` (scheduled, Friday 14:02 UTC, commit `0c9859f`) Success; baseline reconciliation 7 PASS with steps 0-3 at 5 / 53 / 18 / 53; one open issue (the Phase 14 misnamed file) |
| Delivery | `simulate` produced `BATCH_20250304T090000`: customers 3 rows, products 2, customer_events 5, each with a control file (row count, SHA-256) |
| Scan | 3 LOADED, each in its own audited Bronze run; files archived to `archive\2026-11-20\` |
| Failures | `customers_latest_FINAL.jsonl` REJECTED and parked in `error\` beside the Phase 14 copy (time suffix, nothing overwritten); the redelivered customer_events file SKIPPED by checksum |
| Production rebuild | `prod_build` run by hand: 98 models, 179 data tests, 4 seeds; 281 total, 253 success, 28 no-op (the 20 intermediate and 8 check models are ephemeral); no warnings, no errors; 88 s |
| Evidence 1-4 | Registry decisions, lineage OK for all 3 files, Silver current rows 3 / 2 / 5, two events 21 days late picked up by the incremental model |
| Evidence 5-7 | Type 2 history, Gold point in time and reconciliation all as expected; all 7 reconciliation checks PASS |
| Monitoring | customers 4 files loaded, 1 failed attempt, 0 open failures, 11 rows; products 2 loaded, 2 skipped, 4 rows; customer_events 2 loaded, 1 skipped, 10 rows, last attempt SKIPPED. All ON_TIME and OK |
| Open issues | 1 row: `REJECTED_NAME customers_latest_FINAL.jsonl`. The view keeps one row per file name (its latest attempt), so a client repeating the same bad name is one problem to fix; the registry keeps every attempt |
