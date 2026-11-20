# RetailFlow · Interview walkthrough

How to present this project in an interview: a short pitch, the architecture in two minutes, the decisions worth defending, the problems solved along the way, and the questions to expect. Every number here comes from a validated phase (see [progress.md](progress.md)).

## The 30-second pitch

> RetailFlow is an end-to-end retail data platform I built on BigQuery, Python, Snowflake and dbt Cloud. Two sources (a BigQuery dataset with deliberately injected defects, and a REST API) land in an append-only Bronze layer. dbt then builds staging, a deduplicated Silver layer with data quality quarantine, SCD Type 2 history, and a Gold star schema with KPI marts. Its main idea is that every record is accounted for: a reconciliation gate follows 127,655 records from source to KPI, and the build fails if any layer loses or duplicates one. Files land through a file-driven pipeline with control files and checksums, and every change reaches production through CI on pull requests.

## The two-minute architecture

```
BigQuery (batches 001-008, defects, nested data) ─┐
Mock REST API  ────────────────────────────────────┼─ Python loader ─► BRONZE.SOURCE_RECORDS (append-only, MERGE on source_record_id)
Client files (regex name + .ctl control file) ────┘        │            AUDIT.BRONZE_LOAD_RUNS, CONTROL watermarks + file registry
                                                           ▼
                        dbt Cloud: STAGING (typed views) ─► SILVER (one disposition per delivery, current entities,
                        SCD2/SCD3 history) ─► DATA_QUALITY (rules, quarantine, waivers, publication status)
                        ─► GOLD (4 dimensions, 4 facts, 5 KPI marts) ─► reconciliation gate + monitoring
                                                           ▼
                        GitHub: PR → Actions (pytest, dbt parse/compile) + dbt Cloud CI (state:modified+) → main
                        → scheduled production job, docs on GitHub Pages
```

| Layer | Tool | Size |
|---|---|---|
| Sources | BigQuery Sandbox, FastAPI mock | 8 batches, 15 entities |
| Ingestion | Python, Snowflake connector | 38 unit and API tests |
| Warehouse | Snowflake, X-Small warehouse | about 30 MB |
| Transformation | dbt Cloud | 98 models, 179 tests, 4 seeds |
| CI/CD | GitHub Actions, dbt Cloud CI, branch ruleset | 3 required checks |

## Decisions worth defending

| Decision | Why | Trade-off |
|---|---|---|
| **Bronze is append-only, keyed by `source_record_id`, loaded with a MERGE in one transaction** | Replays and redeliveries insert nothing new, so any load can be rerun safely. Every delivery is kept, which is what lets Silver explain itself | Storage grows with every delivery (negligible here) |
| **Every Bronze delivery gets exactly one disposition** (ACCEPTED, SUPERSEDED, DUPLICATE, DELETED, REJECTED) | "Where did this record go?" always has an answer, which reconciliation relies on | More logic in Silver than a simple `ROW_NUMBER() = 1` |
| **Data quality rejects a change before it becomes current**, quarantines it with evidence, and Gold publishes only `PUBLISHABLE` orders | A bad price never reaches history or KPIs, not even for a closed period. Waivers are explicit rows, not code edits | Cross-entity rules force some Silver models to rebuild fully |
| **Incremental models use arrival time as the watermark** | Late events (21 days late in the demo) are still picked up. Business-time watermarks would miss them | Needs an equivalence test: incremental, replayed and full builds were proven identical by hash |
| **SCD Type 2 built from trusted versions, not dbt snapshots** | Snapshots record what the warehouse saw and when. This history records what was true and when, including late changes at their business date, and never includes rejected changes | Custom macro to maintain |
| **Gold joins facts to the dimension version valid at order time** | A customer's tier change does not rewrite last quarter's segment revenue | Facts carry version keys, not natural keys |
| **Reconciliation is a failing test, not a report** | Seven steps from source manifest and control files through Bronze, audit, Silver, Gold and marts. 9 exclusions are registered, not silently filtered | Every new exclusion needs a register entry |
| **Files are identified by regex in a config table, proven complete by a control file** | No batch name or row count typed by hand. A new feed is a config row. SHA-256 skips redeliveries | The client must follow the naming and control-file contract |
| **Two CI layers** | Offline parse and compile catch most mistakes in seconds for free; the warehouse build runs only changed models, in isolated schemas | The free dbt plan allows 3,000 models a month, so production builds three times a week, not daily |

## Problems solved along the way (STAR material)

1. **First dbt build failed in Snowflake but parsed locally.** Situation: staging models compiled offline, then failed in dbt Cloud on a role mismatch and on `TRY_TO_NUMBER` receiving VARIANT input. Action: fixed the grants for `RETAIL_DBT_ROLE` and the type handling in staging. Result: led to the rule that every new schema ships with its grants, and to the two-layer CI later (offline checks can't catch warehouse errors).
2. **Build vs buy with Fivetran.** I set up a managed BigQuery-to-Snowflake connector to compare with the Python loader. The initial sync needs BigQuery billing because the Sandbox blocks DML. I paused it and documented how to resume, rather than enabling billing for a comparison. Point: a managed tool is not free of source-side constraints.
3. **Making incremental safe.** Showed that a late payment and a reverted duplicate behave the same in incremental, replay and full-refresh builds, compared by hash. Without that proof, incremental is a performance gamble.
4. **Recovering a failed delivery.** The control file promised 4 rows and the file had 3. The pipeline marked it FAILED, parked it, and loaded nothing. The client resent it with a correct control file, it loaded, and monitoring closed the issue automatically.
5. **Cost review.** 5.9 credits in 10 days. The models were fast (slowest about 2 s); the cost was a worksheet warehouse idling five minutes after every session. 60-second auto-suspend and a monthly resource monitor fixed it. Lesson: look at metering before tuning queries.
6. **CI without secrets.** GitHub Actions runs `dbt parse` and `dbt compile` with placeholder credentials, excluding the two incremental models because they ask the warehouse whether their table exists. The real Snowflake build is dbt Cloud's job, in `dbt_cloud_pr_*` schemas dropped when the PR closes.

## Numbers to remember

| | |
|---|---|
| Records reconciled source → KPI | 127,655 |
| BigQuery dispositions (Phase 9) | 126,305 accepted, 1,048 superseded, 240 duplicate, 21 rejected, 1 deleted |
| Quarantined | 21 OPEN rows; publication 22,105 publishable orders |
| Recognized merchandise | USD 9,669,722.83 (BigQuery) + 160.00 (API), matched to the cent by an independent Python recomputation |
| Margin | 40.59 % January, 40.71 % February |
| Reconciliation | 7 checks, all PASS |
| Files demo | 4 loaded, 2 skipped redeliveries, 1 rejected name, 1 failed then recovered |
| dbt | 98 models, 179 tests |
| Cost | about 6 credits in the first 10 days; projected 2-3 credits a month |

## Questions to expect

**How do you handle a duplicate delivery?** Bronze MERGE on `source_record_id` inserts nothing for an exact replay. A file with identical content is skipped by SHA-256 before loading. A business duplicate with a new record ID is marked DUPLICATE in Silver and kept for audit.

**What happens when a record arrives late?** It lands in Bronze with its real arrival time. The incremental watermark is arrival time, so it is processed. History places it at its business date.

**Why not dbt snapshots for SCD2?** Snapshots capture warehouse state at run time. I needed history by business effective time, excluding quarantined changes, and rebuildable from Bronze at any time.

**How do you know the numbers are right?** Gold was compared to an independent Python recomputation of the fixture rules, to the cent. Reconciliation runs on every build and fails it on any gap.

**How would this run in production on Azure?** Event Grid on the landing container triggers an ADF pipeline that calls a Snowflake stored procedure to load the file, moves it, and calls dbt Cloud. The registry, regex config, MERGE and dbt stay the same. The ADF code is in `azure/`, not deployed (no subscription).

**What would you change at scale?** A service user with key-pair auth for production; dbt Cloud API triggering after loads; state-aware or slim production builds; Snowpipe or ADF instead of the local sensor; and alerting from the monitoring tables to email or Slack.

**What is not finished?** The Fivetran comparison is paused (needs BigQuery billing). The Azure version is code only. Production uses a personal login rather than a service user. All three are documented with next steps.

## Showing it

Follow the [Phase 16 demo](phase-16.md): about 20 minutes from a client delivery to the KPI layer, with failure handling, CI and the reconciliation gate.
