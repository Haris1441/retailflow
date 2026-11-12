# Phase 2 · BigQuery initial source

RetailFlow needs an interconnected baseline so ingestion and dbt can later explain revenue, refunds, inventory and data defects against known source totals. BigQuery owns these fixtures. The independent API will supply separate transactions later.

## Run in BigQuery Studio

1. Open BigQuery Studio in your confirmed Sandbox project. In the editor query settings, use GoogleSQL and set processing location to US. The SQL uses the active project and the dedicated retailflow_source dataset. If your account requires another location, change the location in the setup SQL and use that processing location for all three scripts.
2. In a new editor tab, paste and run [create_dataset.sql](../sql/bigquery/00_setup/create_dataset.sql). Expect the dedicated dataset to appear in Explorer. This creates a cloud resource in your selected project.
3. In a new editor tab, paste and run the entire [batch_001.sql](../sql/bigquery/02_initial_seed/batch_001.sql). Leave the base date at 2025-01-01 or choose one fixed date before the first run. Expect 15 tables and 119,937 rows. Each CTAS statement defines a table and populates it in one operation.
4. In a new editor tab, paste and run the entire [validate_batch_001.sql](../sql/bigquery/04_validation/validate_batch_001.sql). Match the seed base date. Expect an empty mismatch result and a successful final assertion. The [manifest](DATA_GENERATION_MANIFEST.md) lists table counts and deliberate defects.
5. Confirm that validation passed before starting Phase 3.

## Verify and recover

The validator checks per-table counts and lineage, mandatory links, known defect totals, order header math, payments, returns, promotions, stock, FX and nested event fields. If an assertion fails, open the SELECT child result in the script execution details to see expected and actual counts. To demonstrate a failure safely, change the date in the validation editor only, run it, and observe the lineage mismatches. Restore the date and rerun.

If dataset creation reports access denied, use an existing authorized Sandbox project or ask its administrator to provision the dedicated dataset. If the seed stops midway, resolve the failing statement and rerun the same seed with the same base date. Existing tables are retained and missing tables are created. This is a multi-statement job with independently committed DDL. Use a fresh dedicated dataset for a different base date or fixture revision by changing the dataset reference consistently in all three files. A preexisting table from another fixture can survive a rerun, so always run validation before extraction.

Sandbox excludes DML and automatically expires tables after 60 days. CTAS supports deterministic fixture generation without INSERT or MERGE. This phase uses create-if-absent for safe retries. Later changes can use separate CTAS batch tables and derived current-state views. In a production environment, use source contracts, independently published immutable batches, access-controlled deployment, schema review and a versioned manifest. A billing-enabled environment can use approved DML and explicitly managed retention. [Sandbox limits](https://docs.cloud.google.com/bigquery/docs/sandbox) · [GoogleSQL DDL](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language)

## Definition of done

The dedicated dataset contains 15 tables, the validator succeeds, and the manifest explains the warning and rejection counts. Local verification covers fixture arithmetic and file consistency. The user confirmed that BATCH_001 passed validation in BigQuery Sandbox.
