# Phase 8 · Silver: normalization and deduplication

Staging keeps one row per Bronze delivery, so the same customer can appear several times: the baseline, an update, a backdated correction, a re-sent copy. Silver turns that delivery history into **one current row per business key**, flattens nested API arrays into child tables, maps API identifiers to BigQuery-owned keys, and records what happened to every delivery.

```
STAGING (one row per delivery)
   │  resolve_versions macro, one ephemeral int_*__versions model per staging model
   ▼
SILVER_RECORD_DISPOSITIONS   every delivery → ACCEPTED | SUPERSEDED | DUPLICATE | DELETED
SILVER_<ENTITY>              ACCEPTED rows only = current state, plus flattened children
```

## Design decisions

**Keys.** Silver keys are source-local: `BIGQUERY:123`, `MOCK_API:API-ORDER-001`. BigQuery and API customers are separate identities. Email is a contact attribute, not a match key. Products and stores are owned by BigQuery; API identifiers map to them through the `api_crosswalk` seed, and the original value stays in `source_product_id` / `source_store_id`.

**Version ordering.** Each business key's deliveries are ordered by business time, not arrival time:

1. `source_effective_at` for change batches (BATCH_002–008).
2. Otherwise the entity's own payload time: `updated_at`, or the rate's `effective_at` for exchange rates. Baseline rows have no envelope effective time, and without this fallback the BATCH_006 PKR correction would lose to the original rate.
3. Otherwise `source_available_at`.

Ties go to the later availability, then the higher record ID. A current row chosen from a genuine tie is flagged `has_version_tie` and reported by a warning test.

**Dispositions.** Every Bronze delivery gets exactly one:

| Disposition | Meaning | Fixture example |
|---|---|---|
| ACCEPTED | Current version of the key | 5,001 BigQuery customers |
| SUPERSEDED | Replaced by a later business version | 500 pending orders completed in BATCH_003 |
| DUPLICATE | Same key, content and operation as an earlier delivery | 240 events re-sent in BATCH_005 |
| DELETED | The current version is a delete tombstone | Event 401 in BATCH_008 |

Duplicates are detected by a hash of the typed business columns, not the raw JSON text, so formatting differences between BigQuery's `TO_JSON` and `TO_JSON_STRING` cannot hide a duplicate.

**Soft vs hard deletes.** Customer 111's soft delete is an ordinary update: the row stays with `is_deleted = TRUE`. Event 401's `DELETE` tombstone removes the key from Silver.

**Flattening.** Each nested array becomes its own child table with its own key: customer addresses, API order lines, API line discounts, API shipments, event products. Sibling arrays are never flattened in the same query, so they cannot multiply each other.

**Out of scope until later phases.** Phase 8 takes the latest version. The BATCH_005 faulty changes (negative prices, missing category, category cycle, negative stock, 99-unit return) and the BATCH_001 defects (order 10, order 30, order 20 line 58) are present in Silver and listed by validation check 6. Phase 9 adds rule results so a rejected change keeps the last trusted version. Phase 10 makes the models incremental. Phase 11 builds SCD history from the version data.

## Files

| Path | Purpose |
|---|---|
| `models/staging/*` | All 20 staging models now typed, with `source_effective_at` exposed |
| `macros/resolve_versions.sql` | Version ordering, duplicate detection and dispositions |
| `models/silver/intermediate/int_*__versions.sql` | One ephemeral model per staging model |
| `models/silver/silver_*.sql` | 20 Silver tables (tag `silver`) |
| `models/silver/_silver.yml` | Key, relationship and value tests |
| `seeds/api_crosswalk.csv` | API product and store IDs mapped to BigQuery keys |
| `tests/assert_dispositions_match_bronze.sql` | Fails if any Bronze delivery lacks exactly one disposition |
| `tests/assert_no_current_version_ties.sql` | Warns on unresolved version ties |
| [grant_dbt_silver.sql](../sql/snowflake/00_setup/grant_dbt_silver.sql) | SILVER schema grants for `RETAIL_DBT_ROLE` |
| [silver.sql](../sql/snowflake/05_validation/silver.sql) | Reconciliation, counts and scenario spot checks |

## Run

1. In Snowsight, run [grant_dbt_silver.sql](../sql/snowflake/00_setup/grant_dbt_silver.sql) as `ACCOUNTADMIN`.
2. In dbt Cloud Studio, switch to branch `phase-8-silver`, pull, and run:

   ```text
   dbt build --select tag:staging tag:silver
   ```

   Staging is rebuilt first because its models changed. The seed loads, the Silver tables build, and the tests run.

3. Expect **no errors** and **two warnings**:
   - `silver_orders.customer_key` relationship: order 10 references missing customer 999999.
   - `silver_products.category_id` relationship: products 41–45 reference missing category 999999.

   Both are documented fixture defects for Phase 9.

4. Run [silver.sql](../sql/snowflake/05_validation/silver.sql) in Snowsight and compare each result with the expected values in its comments.

## Definition of done

`dbt build --select tag:staging tag:silver` succeeds with only the two expected warnings. Every Bronze delivery has exactly one disposition, BigQuery dispositions are 126,309 / 1,065 / 240 / 1, Silver row counts match check 4, and the spot checks return their expected values.

## Outcome

Built in dbt Cloud from `phase-8-silver` on 2026-11-10 with the two expected relationship warnings. Validation passed:

- Every Bronze delivery has exactly one disposition.
- BigQuery dispositions: 126,309 ACCEPTED, 1,065 SUPERSEDED, 240 DUPLICATE, 1 DELETED.
- All 19 Silver row counts matched, for example customers 5,009, orders 22,108, order lines 52,116, payments 22,909 and events 12,007.
- Spot checks passed: the soft delete, the hard delete, the cancellation, email normalization, preferred language, device OS, the API store mapping and the FX correction.
- Check 6 found the six known defect groups (1, 10, 5, 1, 1, 1 rows) that Phase 9 will reject or quarantine.
