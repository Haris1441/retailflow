# Phase 3 · Source change fixtures

The baseline represents one observation. These batches add new transactions, versions, deliberate defects and explicit deletes so later ingestion and dbt work can distinguish business history from arrival order.

Each batch is a separate immutable CTAS table. Its envelope holds batch ID, entity, business key, operation, business effective time, source availability, physical record ID and JSON payload. Each insert or update carries the fixture's row image. A tombstone carries the key only. Separate availability from effective time so a newly delivered historical correction can be extracted and applied in the right history interval. The union view is the extraction entry point for the change fixtures. A repeated physical identity is a transport replay. BATCH_005's duplicated events have distinct physical identities and the same logical keys as their baseline originals.

## Run in BigQuery Studio

1. Select the project containing the validated BATCH_001 dataset. Use the same processing location and GoogleSQL settings as Phase 2. If you used a different dataset name, update the dataset references consistently in both scripts.
2. Paste and run [generate_changes.sql](../sql/bigquery/03_change_batches/generate_changes.sql) in a new query tab. It infers the base date from the baseline category lineage. Expect seven tables named changes_002 through changes_008 and four views.
3. Paste and run [validate_changes.sql](../sql/bigquery/04_validation/validate_changes.sql). Expect an empty mismatch result, successful assertions and final counts of 6,070, 1,020, 4, 260, 302, 20 and 2. Compare with the [manifest](DATA_GENERATION_MANIFEST.md).
4. Run the optional inspection queries below.

```sql
SELECT customer_id, preferred_language, addresses
FROM `retailflow_source.customer_address_examples`
ORDER BY customer_id;

SELECT customer_id, address.*
FROM `retailflow_source.customer_address_examples`
CROSS JOIN UNNEST(addresses) AS address
ORDER BY customer_id, address.address_id;

SELECT order_id, example_payload
FROM `retailflow_source.nested_order_examples`;

SELECT batch_id, business_key, effective_at, source_available_at, payload
FROM `retailflow_source.source_changes`
WHERE scenario IN ('late_dimension', 'late_fx', 'hard_delete_tombstone')
ORDER BY batch_id, business_key;
```

Expect 10 customer parents and 20 address children. The nested order view is a BigQuery shape example built from an existing fixture order. It is excluded from the change feed and should never be ingested as a second transaction. Phase 4 will implement the independent API. Existing web events already contain device, session, attribution and product fields. BATCH_007 extends the device object without altering the baseline table.

## Failure demonstration and recovery

The validator checks deliberate defects as expected input. Change the expected row_count for the negative_price scenario from 10 to 9 in a copy of the validator and run it to see the count mismatch and failed assertion. Then rerun the repository version. If a generation statement fails midway, fix the failing statement and rerun against the same baseline. Existing tables and views are retained. If an earlier object was built from a different fixture revision, use a fresh dedicated fixture dataset for that revision. Missing baseline tables can indicate the Sandbox expiration window. Regenerate the baseline from the original fixed date and validate before recreating changes.

The hard-delete example uses a key-only tombstone and a delete-only view. The original event stays queryable for replay. The soft-delete update retains the customer record and marks it inactive. Production would consume an authoritative CDC stream or outbox with durable offsets, explicit schema versions and a publication checkpoint. The Sandbox simulation uses CTAS because DML is unavailable. [BigQuery Sandbox limits](https://docs.cloud.google.com/bigquery/docs/sandbox) · [GoogleSQL JSON functions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/json_functions)

## Definition of done

The generation and validation scripts pass in BigQuery, the four views are available, and the physical row counts and expected dispositions agree with the manifest. The change feed and source examples are ready for subsequent ingestion and transformation phases.

### Repair for the original event ranges

BATCH_001 reserves six event IDs per session and emits five events. The original BATCH_005 and BATCH_007 ranges therefore selected 200 duplicate events and nine nested device updates. If you already ran that version, inspect the mismatch SELECT in the validator's child jobs. Run [repair_event_ranges.sql](../sql/bigquery/03_change_batches/repair_event_ranges.sql) only against your dedicated synthetic dataset if those are the two mismatches. It replaces the generated changes_005 and changes_007 tables. Run the full validator again. A fresh installation uses the corrected generator directly.
