# RetailFlow roadmap

- [x] 0. Architecture and environment assessment.
- [x] 1. Business requirements, source-to-target mapping, and conceptual data model.
- [x] 2. BigQuery datasets, schema creation, and initial dummy data generation. User confirmed that BATCH_001 passed BigQuery Sandbox validation.
- [x] 3. Data defect injection, nested data, and subsequent source-change batches. BigQuery Sandbox validation succeeded after repairing two event ID ranges.
- [x] 4. Mock API development and API ingestion testing. All 13 automated tests passed and the user reproduced both live smoke checks.
- [x] 5. Snowflake setup and Bronze ingestion. All 20 local regression tests passed. BigQuery baseline and change batches, API duplicate load, replay, count reconciliation, and duplicate-identity validation passed in Snowflake.
- [x] 6. Metadata-driven pipeline and watermark management. Control metadata, successful incremental runs, and overlap replay were validated in Snowflake.
- [x] 7. dbt project setup and staging transformations. Built in dbt Cloud from Haris1441/retailflow branch phase-7-staging: 20 staging views and 15 tests passed. STG_BQ_CUSTOMERS returned 5,025 rows and the order lineage check returned 0 missing Bronze identities.
- [ ] 7b. Fivetran build-vs-buy comparison (optional, independent of dbt). PAUSED 2026-11-10: Snowflake destination and BigQuery connection `fivetran_bqq` work, but the initial sync needs BigQuery billing (Sandbox blocks DML). Resume by enabling billing on bq-dbt-sf, then follow docs/fivetran.md steps 4-6.
- [x] 8. Silver transformations, normalization, and deduplication. Built in dbt Cloud from branch phase-8-silver. Every Bronze delivery has one disposition; BigQuery dispositions 126,309 accepted, 1,065 superseded, 240 duplicate, 1 deleted. All 19 Silver row counts and the scenario spot checks matched. The six known Phase 9 defects are present as expected.
- [x] 9. Data quality, quarantine, and remediation. Rules, quarantine, publication status and waivers on branch phase-9-data-quality. Validated in Snowsight 2026-11-10: dispositions 126,305/1,048/240/21/1, 21 OPEN quarantine rows, publication 22,105/1/2, Phase 8 defects all zero.
- [x] 10. Incremental processing, CDC simulation, late-arriving records, and replay. Branch phase-10-incremental: CDC cutoff var, incremental payments and events, revert-aware duplicates, equivalence test. Validated 2026-11-10: builds A–E passed; BigQuery rows rewritten B 502/0, C 100/250, D 100/10; replay unchanged and incremental equals full refresh (hashes TRUE); 100 late payments present; event 401 removed; Phase 9 dispositions unchanged.
- [x] 11. SCD Type 1, Type 2, and Type 3 demonstration. Branch phase-11-scd: customer and product Type 2 from trusted versions, loyalty Type 3, integrity test. Validated 2026-11-11: customer history 5,020 + 8 rows (19 keys with history), product history 1,011 rows (10 keys), customer 12 GOLD from 2025-01-13 despite arriving 2025-02-24, products 31–45 one row each, 11 Type 3 tier changes, point-in-time tiers differ from current.
- [x] 12. Gold dimensional modeling and business metrics. Branch phase-12-gold: 4 dimensions, 4 facts, 5 KPI marts, balance test. Validated 2026-11-11: every gold.sql check matched the independent Python recomputation to the cent (recognized merchandise USD 9,669,722.83 + 160.00 API, net revenue Jan 9,171,538.24 / Feb 445,185.23, margin 40.59 % / 40.71 %, segments, top 10, CLV, return, refund and stockout rates, point-in-time tiers).
- [x] 13. Source-to-target reconciliation. Branch phase-13-reconciliation: source manifest seed, six reconciliation checks, exclusion register, summary gate test. Validated 2026-11-11: all 6 checks PASS; 127,655 records reconciled source → Bronze → load audit (13 runs, 3 replays) → dispositions; Silver = Gold + 9 registered exclusions; 19 measure/currency money rows balance exactly; 9 mart measures equal the facts.
- [x] 14. Orchestration, monitoring, and recovery. File-driven landing pipeline: regex feed identification from CONTROL.FILE_CONFIG, control files (row count, SHA-256), per-attempt CONTROL.FILE_REGISTRY, reuse of the transactional Bronze MERGE, recovery of interrupted files, reconciliation step 0, monitoring models and a warn-level alert. Azure Data Factory version kept as deploy-ready code (no Azure subscription). Validated 2026-11-12: 4 LOADED files (13 rows), 2 SKIPPED redeliveries, 1 REJECTED name, 1 FAILED control count recovered by resend; lineage file -> run -> Bronze OK; 6 customers, 2 products, 5 events (2 late by 21 days) current in Silver with SCD history; all 7 reconciliation checks PASS (52 batches, 17 audited runs); monitoring ON_TIME/OK with only the rejected name open. Repository became a monorepo (PR #10).
- [ ] 15. Automated testing, CI, documentation, and cost review.
- [ ] 16. Final operational demonstration, portfolio preparation, and interview walkthrough.

## Phase 0 acceptance

- [x] Inspect workspace and capture local versions.
- [x] Document the transfer boundary, schema responsibilities and conceptual source relationships.
- [x] Check official product constraints and provide validation commands.
- [x] Confirm BigQuery Sandbox query, Snowflake sign-in and warehouse visibility, and dbt Developer Studio access.
- [x] Confirm readiness to begin Phase 1.
