# Phase 10 · Incremental processing, CDC replay and late arrivals

Through Phase 9, every build recomputed Silver from all of Bronze. That is simple and always correct, but cost grows with history. Phase 10 makes the two largest Silver tables with key-local rules incremental. It replays the BigQuery change batches one at a time as a CDC feed, and proves that an incremental build, a replayed build and a full rebuild produce identical data.

Bronze was already incremental and idempotent: physical identity, watermarks and overlap re-reads were covered in Phases 5 and 6. This phase covers the transformation side.

## CDC simulation

All eight BigQuery batches are already in Bronze. The dbt var `cdc_through_batch` hides later batches, so each build sees Bronze as it stood when a given batch had just arrived:

```text
--vars '{cdc_through_batch: BATCH_004}'   baseline + BATCH_002..004 visible
```

The filter sits in the `bronze_source` macro, which every staging view uses, so the whole pipeline (Silver, data quality, dispositions) sees the same cutoff. The default is `BATCH_999`, meaning everything. Always build staging together with Silver, because the cutoff is compiled into the staging views.

| Batch | Arrives (day) | What it does to payments and events |
|---|---|---|
| BATCH_001 | 42 | Baseline: 20,800 payments, 12,000 events |
| BATCH_002 | 46 | 2,000 new payments |
| BATCH_003 | 48 | 500 payment updates (pending to success) |
| BATCH_004 | 50 | One failed payment, one new refund |
| BATCH_005 | 52 | 240 duplicate events |
| BATCH_006 | 54 | 100 **late-arriving** payments, business time 45 days earlier |
| BATCH_007 | 56 | 10 events gain a device OS field |
| BATCH_008 | 58 | Hard-delete tombstone for event 401 |

## How the incremental models work

`silver_payments` and `silver_customer_events` are `incremental` with `delete+insert` on their Silver key.

1. **Watermark on arrival time.** Each row stores `last_delivery_available_at`, the latest arrival of any delivery of its key. On an incremental run, a key is *affected* if it has a delivery that arrived after the table's maximum of that column, per source system.
2. **Rebuild the whole key, not just the new row.** Every delivery of an affected key goes through `resolve_versions` again. A late record therefore takes its correct place in the key's history: it wins only if its business time is the latest.
3. **Write the key's top version, whatever its disposition.** `delete+insert` replaces the old row. A post-hook then deletes rows whose `key_disposition` is not `ACCEPTED`. This is how a hard-delete tombstone (event 401) or a newly quarantined key leaves the table. Without this step, `delete+insert` would never remove a key that has no new row.
4. **Optional lookback.** `silver_lookback_hours` re-reads a window before the watermark. The default is 0 because batch arrival times are immutable. Re-reading is always safe because keys are rebuilt from full history.

### Why arrival time and not business time

The 100 BATCH_006 payments happened on day 9 but arrived on day 54. A watermark on `payment_at` would already be past day 9, so it would skip all 100. Arrival time only moves forward, so nothing is skipped. In production, use the warehouse's own ingestion timestamp or a Snowflake stream on Bronze. Source availability is used here because it is deterministic for the replay.

### Why only two tables

Both tables have rules that look only at the key itself. Orders, order lines, products and categories have **cross-entity** REJECT rules: a product depends on trusted categories, an order on its customer and lines. A category change can flip a product's status without any new product delivery, so "only keys with new deliveries" would be wrong for them. Making them incremental needs dependency expansion: also reprocess children of changed parents. They stay full rebuilds, which is also cheaper at this size. Small dimensions stay full rebuilds for the same cost reason.

### Proving correctness

- `tests/assert_incremental_matches_full_rebuild.sql` runs on every build. It recomputes each key's winner from all visible deliveries and compares it with the incremental table. Expect zero rows.
- `key_disposition` must be `ACCEPTED` on every remaining row, which proves the post-hook ran.
- The Snowsight runbook below compares content hashes across incremental, replayed and fully rebuilt states.

## Revert-aware duplicates

`resolve_versions` used to call a delivery a duplicate if it matched *any* earlier delivery of the key. Under CDC a value can change back (A → B → A). The second A would then have been discarded and B would stay current, which is wrong. A duplicate is now a delivery identical to the delivery *just before it* in arrival order, using `CONDITIONAL_CHANGE_EVENT` over the content hash. The fixtures have no reverts, so every Phase 9 number stays the same.

## Run

You need `CREATE TABLE` on `RETAIL_DWH.AUDIT` in Snowsight for the capture table.

0. In Snowsight, run section 0 of [incremental.sql](../sql/snowflake/05_validation/incremental.sql) once.
1. In dbt Cloud, switch to `phase-10-incremental` and pull. Run the five builds below in order. **After each build**, run section 1 of `incremental.sql` with that step's label (`SET step = 'A';` and so on).

| Step | dbt Cloud command | What it shows |
|---|---|---|
| A | `dbt build --select tag:staging tag:silver tag:data_quality --full-refresh --vars '{cdc_through_batch: BATCH_002}'` | Initial full load. A full refresh is required once, because the two tables change from table to incremental. |
| B | `dbt build --select tag:staging tag:silver tag:data_quality --vars '{cdc_through_batch: BATCH_004}'` | CDC updates: only the 502 changed payment keys are rewritten |
| C | `dbt build --select tag:staging tag:silver tag:data_quality --vars '{cdc_through_batch: BATCH_008}'` | Duplicates, late arrivals, a schema change in JSON and a hard delete |
| D | `dbt build --select tag:staging tag:silver tag:data_quality --vars '{cdc_through_batch: BATCH_008, silver_lookback_hours: 96}'` | Replay: re-reads the last batches, changes nothing |
| E | `dbt build --select tag:staging tag:silver tag:data_quality --full-refresh` | Full rebuild with all batches, the reference result |

Every build should pass with no errors and no warnings.

2. Run sections 2 to 6 of `incremental.sql` and compare with the expected values in the comments.

If build B fails with an `on_schema_change` error, step A ran without `--full-refresh`. Rerun A with it.

## Files

| Path | Purpose |
|---|---|
| `macros/cdc.sql` | `cdc_visible`, `incremental_affected_keys`, `silver_incremental_columns` |
| `macros/bronze_source.sql` | Applies the CDC cutoff to every staging view |
| `macros/resolve_versions.sql` | Revert-aware duplicate detection |
| `models/silver/silver_payments.sql`, `silver_customer_events.sql` | Incremental `delete+insert` with the removal post-hook |
| `tests/assert_incremental_matches_full_rebuild.sql` | Incremental equals a full recompute |
| `tests/assert_dispositions_match_bronze.sql` | Now compares with the visible Bronze rows only |
| `dbt_project.yml` | Vars `cdc_through_batch` and `silver_lookback_hours` |
| [incremental.sql](../sql/snowflake/05_validation/incremental.sql) | Captures and checks for steps A to E |

Run the capture exactly once after each build, and use `--full-refresh` only on A and E. A full refresh on B, C or D rebuilds everything, which makes the hash proof meaningless.

## Definition of done

All five builds pass with no warnings. The captures match the expected rows written per step. Replay changed nothing (C = D), incremental equals full refresh (C = E), the 100 late payments are present, event 401 is gone, and the Phase 9 dispositions are unchanged after E.

## Outcome (2026-11-10)

All five builds passed with no errors or warnings, and every check matched.

| Step | Payments, BigQuery rows / rewritten | Events, BigQuery rows / rewritten | MOCK_API rewritten |
|---|---|---|---|
| A full refresh, BATCH_002 | 22,800 / 22,800 | 12,000 / 12,000 | 8 / 8 |
| B incremental, BATCH_004 | 22,801 / **502** | 12,000 / **0** | 0 / 0 |
| C incremental, BATCH_008 | 22,901 / **100** | 11,999 / **250** | 0 / 0 |
| D replay, 96 h lookback | 22,901 / **100** | 11,999 / **10** | 1 / 1 |
| E full refresh | 22,901 / 22,901 | 11,999 / 11,999 | 8 / 8 |

- The content hash for C equals D (replay changed nothing) and E (incremental equals full refresh) for both tables and both sources.
- All 100 BATCH_006 payments are present. Each has business time 2025-01-10 but arrived 2025-02-24, so a business-time watermark would have skipped every one.
- Event 401 is gone, 10 events carry a device OS, and the Phase 9 dispositions are unchanged (126,305 / 1,048 / 240 / 21 / 1).
- Snowflake query history confirmed the work done. dbt's temporary table held 504 payment rows in B, 102 in C and 2 in a no-change run. The `rows_produced` figure on DELETE and INSERT statements reflects micro-partition rewrites, not changed rows, so use the temporary table size instead.

### Known limit: keys with no current row

The watermark comes from rows in the table. A key whose top version is not ACCEPTED (deleted or quarantined) is written, then removed by the post-hook, so its arrival time never raises the watermark. Two MOCK_API keys are therefore re-read on every incremental run. It is harmless because they are rebuilt identically and removed again, but the work never stops repeating. A production design keeps the watermark in a control table (as Phase 6 does for Bronze) or keeps tombstone rows with an `is_current` flag.
