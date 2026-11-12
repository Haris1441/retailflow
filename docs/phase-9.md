# Phase 9 · Data quality, quarantine and remediation

Phase 8 took the latest version of every record, so bad changes became current: negative prices, a category cycle, a 99-unit return. Phase 9 checks every delivery against business rules **before** choosing the survivor. A rejected change never replaces trusted data, the record goes to quarantine with its evidence, and Gold gets a clear list of which orders it may publish.

```
STAGING ──► checks (REJECT rules, every delivery) ──► resolve_versions: latest TRUSTED version wins
                                                         │
                     ┌───────────────────────────────────┼──────────────────────────────┐
                     ▼                                   ▼                              ▼
      DATA_QUALITY.DQ_RULE_RESULTS         DATA_QUALITY.DQ_QUARANTINE      SILVER.SILVER_ORDER_PUBLICATION
      one row per failed rule              rejected deliveries + payload   PUBLISHABLE / HELD / QUARANTINED
```

## Two kinds of rules

| Severity | When it runs | Effect | Examples |
|---|---|---|---|
| **REJECT** | On every delivery, before version selection | The delivery cannot become current. The latest trusted version stays; with none, the key is quarantined. | Negative price, missing category, category cycle, negative stock, zero quantity, impossible return, missing customer, header amount mismatch |
| **WARN** | On current Silver rows | Reported only; the row stays current | Missing or malformed email, shared email, missing description, missing supplier contact |

The full catalog, with rule IDs and descriptions, is the `dq_rules` seed. Every failure is stored separately in `DQ_RULE_RESULTS`, so one delivery can fail several rules.

### Rules that depend on other entities

Reference rules check against **trusted current** data: a product's category must be a trusted category, a return's line must be a trusted line. This gives a fixed dependency order with no cycles: categories → products → order lines → orders and returns, plus customers → orders.

**The category cycle is time-aware.** Each category change is checked against the tree as it stood at that change's business time. The BATCH_005 change (category 1 → parent 7) closes the loop 7 → 4 → 1 and is the one rejected. The older categories it loops through are not blamed.

**Order balance uses the delivered lines.** The header check compares the header total with its lines minus the order discount plus shipping, within 0.01. It uses each line's latest version even if that line is rejected. Order 20's zero-quantity line kept its original amounts, so the header is correct and the order is **held**, not rejected.

## Dispositions and publication

`resolve_versions` sorts rejected deliveries after every trusted version, then adds a fifth disposition:

| Disposition | Meaning |
|---|---|
| ACCEPTED | Current trusted version |
| SUPERSEDED | Older trusted version |
| DUPLICATE | Identical copy of an earlier delivery |
| **REJECTED** | Failed an unwaived REJECT rule |
| DELETED | Current version is a delete tombstone |

`SILVER_ORDER_PUBLICATION` lists every order key with a status Gold must respect:

| Status | Rule | Fixture orders |
|---|---|---|
| PUBLISHABLE | Trusted header and no rejected lines | 22,105 |
| HELD | Trusted header, at least one rejected line | Order 20 |
| QUARANTINED | No trusted header | Orders 10 and 30 |

Children of held and quarantined orders (their other lines, payments and promotions) are valid records and stay in Silver. Gold excludes them and reconciles the exclusion separately.

## Remediation

There are two ways to clear a quarantined record:

1. **Fix it at the source (preferred).** The source sends a corrected delivery. It passes the rules, wins on business time, and the rejected delivery stays as history. Phase 10 adds the replay mechanics.
2. **Approve an exception (waiver).** When the business accepts the data as it is, add a row to `seeds/dq_waivers.csv` with the delivery key, rule, `ACCEPT`, a reason, the approver and a date. The failure is still recorded, marked `is_waived`, and quarantine shows `WAIVED`.

### Exercise: waive order 30

Suppose finance confirms that order 30's extra 7 units are a legitimate manual adjustment.

1. Add this line to `seeds/dq_waivers.csv`:
   ```text
   BIGQUERY:orders:orders:BATCH_001:30,ORD_AMOUNT_MISMATCH,ACCEPT,Finance confirmed manual adjustment of 7,your.name,2026-11-10
   ```
2. Run `dbt build --select tag:staging tag:silver tag:data_quality`.
3. Expect order 30 to become ACCEPTED, REJECTED to drop to 20, quarantine to show order 30 as `WAIVED`, publication to show order 30 as `PUBLISHABLE`, and Silver orders to rise to 22,107.
4. Remove the line and build again to return to the baseline state. Waivers belong in Git so every exception has a review trail.

## Files

| Path | Purpose |
|---|---|
| `seeds/dq_rules.csv` | Rule catalog (18 rules) |
| `seeds/dq_waivers.csv` | Approved exceptions; the example row is inert |
| `macros/resolve_versions.sql` | Adds `checks`, `is_rejected` and the REJECTED disposition |
| `macros/dq_with_waivers.sql` | Adds failure keys and waiver decisions to every check |
| `models/data_quality/checks/*` | 7 REJECT check models and 1 WARN check model (ephemeral) |
| `models/data_quality/dq_rule_results.sql` | All failures, one row per rule per delivery |
| `models/data_quality/dq_quarantine.sql` | Rejected deliveries with raw payload and status |
| `models/silver/silver_order_publication.sql` | Publication status per order key |
| `tests/assert_rejections_match_quarantine.sql` | Rejected deliveries and open quarantine always agree |
| [grant_dbt_data_quality.sql](../sql/snowflake/00_setup/grant_dbt_data_quality.sql) | DATA_QUALITY grants for `RETAIL_DBT_ROLE` |
| [data_quality.sql](../sql/snowflake/05_validation/data_quality.sql) | Validation with expected values |

## Run

1. In Snowsight, run [grant_dbt_data_quality.sql](../sql/snowflake/00_setup/grant_dbt_data_quality.sql) as `ACCOUNTADMIN`.
2. In dbt Cloud Studio, switch to `phase-9-data-quality`, pull, and run:
   ```text
   dbt build --select tag:staging tag:silver tag:data_quality
   ```
   Expect **no errors and no warnings**. The two Phase 8 relationship warnings are now hard tests, and they pass because the defects are quarantined.
3. Run [data_quality.sql](../sql/snowflake/05_validation/data_quality.sql) and compare each result with its expected values.
4. Optional: do the order 30 waiver exercise.

The Phase 8 counts in `silver.sql` no longer apply to orders, order lines and returns. Use check 6 here instead.

## Definition of done

The build passes with no warnings. Dispositions are 126,305 / 1,048 / 240 / 21 / 1, REJECT results match the 21 manifest defects, WARN counts match, quarantine has 21 OPEN rows, publication is 22,105 / 1 / 2, the defect list in check 7 is all zeros, and check 8 shows the trusted fallbacks.

## Outcome (2026-11-10)

Every validation check in `data_quality.sql` matched its expected value.

| Check | Result |
|---|---|
| Dispositions | ACCEPTED 126,305 · SUPERSEDED 1,048 · DUPLICATE 240 · REJECTED 21 · DELETED 1 |
| REJECT failures | 21 across 8 rules, all matching the manifest, none waived |
| WARN results | Missing email 101 · malformed 50 · shared 2 · missing description 10 · missing supplier contact 1 |
| Quarantine | 21 OPEN rows, each with its observed values (for example `returned=99, sold=2`) |
| Publication | PUBLISHABLE 22,105 · HELD 1 (order 20) · QUARANTINED 2 (orders 10 and 30) |
| Silver counts | orders 22,106 · order_items 52,115 · returns 501 · products 1,001 · categories 9 · inventory 8,408 |
| Phase 8 defects | 0 on all seven rows |
| Trusted fallback | 17 rows, all from BATCH_001 |
