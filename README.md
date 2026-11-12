# RetailFlow

RetailFlow is a hands-on retail analytics platform for tracking sales, returns, inventory, customer value and fulfillment across web, mobile and stores. Python will move synthetic BigQuery and API data into Snowflake. dbt will run SQL in Snowflake to build validated retail entities and reporting models.

## Repository layout

Everything lives in this one repository: https://github.com/Haris1441/retailflow. Changes go through a branch and a pull request into `main`.

| Folder | What it holds |
|---|---|
| `dbt_retailflow/` | The dbt project (staging, Silver, data quality, Gold, reconciliation, monitoring). dbt Cloud points at this folder through its project subdirectory setting |
| `ingestion/`, `pipeline/`, `landing/` | Python: Bronze loader, watermark pipeline, file-driven landing pipeline |
| `api/` | Local mock API used as the second source |
| `sql/bigquery/`, `sql/snowflake/` | Source fixture generation, Snowflake setup, grants and validation queries |
| `azure/` | Deploy-ready Azure Data Factory version of the file pipeline (infrastructure as code, not deployed) |
| `tests/unit/` | Python unit tests (`.venv\Scripts\python.exe -m pytest tests/unit`) |
| `docs/` | Phase runbooks, roadmap, learning journal |

Never committed: `.env`, `profiles.yml`, private keys, `connections.toml`, `.venv/`, the local landing folders and `azure/deployment.json` (see `.gitignore`).

## Start here

1. Clone the repository and open PowerShell in its root.
2. Review the [architecture and conceptual ERD](docs/architecture.md).
3. Run the account checks in the [Phase 0 runbook](docs/phase-0.md) in your browser.
4. Review the [roadmap and acceptance checklist](docs/progress.md) and record your findings in the [learning journal](docs/learning_journal.md).

```powershell
git clone https://github.com/Haris1441/retailflow.git
Set-Location retailflow
& .\scripts\check-local.ps1
```

Phase 0 adds documentation and a local diagnostic. Source SQL, API, ingestion and dbt directories will be added as their phases deliver runnable code. Configuration keys and dependency pins will be introduced with their first consumers. Cloud resource setup requires explicit approval.

[Phase 1 design review](docs/phase-1.md) covers the source mapping, business rules and local SQL example.

[Phase 2 BigQuery runbook](docs/phase-2.md) gives the exact Sandbox execution and validation steps.

[Phase 3 source changes](docs/phase-3.md) covers immutable Sandbox batches, nested payloads and validation.

[Phase 4 mock API runbook](docs/phase-4.md) covers local startup, endpoint tests and failure scenarios.

[Phase 5 Snowflake Bronze runbook](docs/phase-5.md) covers cloud setup, authenticated loads and replay validation.

[Phase 6 metadata and watermarks](docs/phase-6.md) covers the CONTROL registry, overlap extraction, and pipeline status.

[Phase 7 dbt staging](docs/phase-7.md) covers the Snowflake dbt project, Bronze source declaration, and typed staging views.

[Fivetran comparison](docs/fivetran.md) runs a managed connector against the same BigQuery baseline and reconciles it with the Python Bronze path.

[Phase 8 Silver](docs/phase-8.md) resolves delivery history into current entities, flattens nested API data, and assigns every Bronze delivery a disposition.

[Phase 9 data quality](docs/phase-9.md) rejects bad changes before they become current, quarantines them with evidence, and tells Gold which orders it may publish.

[Phase 10 incremental processing](docs/phase-10.md) replays the change batches as a CDC feed, makes payments and events incremental with an arrival-time watermark, and proves that incremental, replayed and full builds match.

[Phase 11 slowly changing dimensions](docs/phase-11.md) builds Type 2 customer and product history from trusted versions (late changes land at their business date, rejected changes never enter history), plus a Type 3 loyalty view.

[Phase 12 Gold](docs/phase-12.md) publishes a star schema (point-in-time customer and product dimensions, sales, returns, payments and inventory facts) and KPI marts, validated against independently recomputed expectations.

[Phase 13 reconciliation](docs/phase-13.md) proves every record and amount from the source manifest through Bronze, the load audit, Silver and Gold to the KPI marts, with an exclusion register, and fails the build if any layer breaks.

[Phase 14 file-driven orchestration](docs/phase-14.md) loads client files the moment they land: the file name identifies the feed and batch by regex, a control file proves the delivery is complete, every attempt is logged, redeliveries are skipped, failures are recoverable, and monitoring shows what needs attention.
