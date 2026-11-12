# Phase 13 · Source-to-target reconciliation

Each earlier phase checked its own layer. Phase 13 connects them into one chain. Every record and every amount is accounted for from the source manifest to the KPI marts, and anything Gold does not publish is listed with its reason. The checks run in every dbt build, and the build fails if any of them breaks.

```
source manifest ──1──► Bronze ◄──2──► load audit
                         │
                         3   one disposition per delivery
                         ▼
                      Silver ──4──► Gold facts + exclusion register   (rows)
                         └────5──► Gold facts + excluded amounts      (money, per currency)
                                        │
                                        6   marts add up to facts
                                        ▼
                                    KPI marts
```

## The six checks

| Step | Layer | Rule | Detail model |
|---|---|---|---|
| 1 | Source → Bronze | Physical rows per source, entity and batch = the manifest (48 rows, 127,655 records) | `recon_source_to_bronze` |
| 2 | Bronze ↔ load audit | Every Bronze row belongs to an audited run, rows per run = `inserted_count`, and inserted + matched = distinct. Replays insert 0 | `recon_bronze_load_audit` |
| 3 | Bronze → Silver | Deliveries = dispositions, per batch, with the disposition breakdown | `recon_bronze_to_silver` |
| 4 | Silver → Gold rows | Silver rows = Gold rows + registered exclusions, per entity | `recon_silver_to_gold` |
| 5 | Silver → Gold money | Silver amount = Gold amount + excluded amount, per measure and currency | `recon_financial` |
| 6 | Gold → marts | Every KPI mart adds up to the facts within one cent | `recon_gold_to_marts` |

`recon_summary` has one row per check. `tests/assert_reconciliation_passes` fails the build when any row is not PASS.

## Design points

- **The source side is explicit.** The `source_manifest` seed writes down what the sources produced, per batch: the manifest tables for BigQuery and the Phase 4 fixtures for the API. Without an independent expected count, "source to target" only compares the warehouse with itself.
- **The load audit closes the loop on retries.** The loader writes `AUDIT.BRONZE_LOAD_RUNS` in the same transaction as the load. So Bronze rows per `run_id` must equal that run's `inserted_count`. A replay shows up as a run that matched everything and inserted nothing. This is "track replay attempts without adding a new business result" in practice.
- **Exclusions are records, not a number.** `recon_gold_exclusions` lists every Silver order, line, payment and return that Gold leaves out, with the publication status and reason from Phase 9. Gold totals plus this register equal Silver, in counts and in money.
- **Money is reconciled per currency.** Local amounts are never added across currencies. Lines whose order header is quarantined (orders 10 and 30) have no trusted currency, so each gets its own `UNRESOLVED <order_key>` bucket instead of being mixed into AED or PKR.
- **Mart checks guard the last step.** A mart that silently drops rows, for example through an inner join to a dimension, is caught here.
- **The CDC cutoff applies.** With `cdc_through_batch` set, checks 1 and 3 compare only the visible batches, so Phase 10 replays still reconcile. Check 2 is physical and always covers all of Bronze.

## Expected results

| Flow | Silver | Gold | Excluded |
|---|---|---|---|
| Orders | 22,106 | 22,105 | 1 (order 20, HELD) |
| Order lines | 52,115 | 52,110 | 5 (orders 10 and 30 QUARANTINED, order 20 HELD) |
| Payments | 22,909 | 22,906 | 3 |
| Returns, inventory, customers, products | 501 · 8,408 · 5,009 · 1,001 | same | 0 |

The excluded money comes out exactly as the fixture rules predict:
- **Line merchandise:** GBP 228.80, plus 2,543.31 and 159,320.00 held separately as unresolved for orders 10 and 30.
- **Order discount:** GBP 2.00.
- **Payments:** AED 2,668.48, GBP 259.04 and PKR 167,295.00. The PKR figure is the same order 30 total that Phase 9 quarantined.

## Run

1. In Snowsight, run [grant_dbt_reconciliation.sql](../sql/snowflake/00_setup/grant_dbt_reconciliation.sql) as `ACCOUNTADMIN`. It grants read access to the load audit.
2. In dbt Cloud, switch to `phase-13-reconciliation` and pull, then run:
   ```text
   dbt build --select tag:staging tag:silver tag:data_quality tag:gold tag:reconciliation
   ```
   Expect no errors and no warnings. The new test must pass.
3. Run [reconciliation.sql](../sql/snowflake/05_validation/reconciliation.sql) and compare with the expected values.

## Files

| Path | Purpose |
|---|---|
| `seeds/source_manifest.csv` | Expected rows per source, entity and batch |
| `models/reconciliation/recon_*.sql` | The six checks, the exclusion register and the summary |
| `tests/assert_reconciliation_passes.sql` | Fails the build on any failed check |
| `models/staging/_staging_sources.yml` | Adds the `audit.bronze_load_runs` source |
| [grant_dbt_reconciliation.sql](../sql/snowflake/00_setup/grant_dbt_reconciliation.sql) | Read access to the load audit |
| [reconciliation.sql](../sql/snowflake/05_validation/reconciliation.sql) | Evidence queries with expected values |

## Definition of done

The build passes with no warnings, all six summary rows are PASS, and the flows and excluded amounts match the table above.

## Outcome (2026-11-11)

All six checks passed, every item with a difference of exactly 0.

| Check | Items | Result |
|---|---|---|
| Source → Bronze | 48 | 127,655 = 127,655, every batch |
| Bronze ↔ load audit | 13 runs | Inserted 127,655 = Bronze 127,655; 3 replay runs |
| Bronze → Silver | 48 | 126,345 accepted · 1,048 superseded · 240 duplicate · 21 rejected · 1 deleted |
| Silver → Gold rows | 7 | 9 registered exclusions (1 order, 5 lines, 3 payments) |
| Silver → Gold money | 19 | Excluded amounts exactly as predicted (GBP 228.80 and 2.00, unresolved 2,543.31 and 159,320.00, payments AED 2,668.48 · GBP 259.04 · PKR 167,295.00) |
| Gold → marts | 9 | Every mart = 9,669,882.83 recognized USD; credits 53,159.36 |

The load audit also shows the ingestion history:
- **MOCK_API:** 4 runs, 3 of them replays. The 49 matched rows are the Phase 5 replay (40) plus the two Phase 6 incremental runs (8 + 1).
- **BigQuery BATCH_001:** loaded in 2 runs, and the second one matched 5,000 rows (the customers) that were already present. That is a partial re-run that added nothing, which is exactly the retry safety the audit is meant to show.

The Phase 5 doc mentions an optional full baseline rerun. No such run appears in the audit, so it was never executed. That is not a failure.
