# Phase 15 · Automated testing, CI/CD, documentation and cost review

Until Phase 14, a change was checked by a person: build it in the dbt Cloud IDE, look at the results, push to `main`. Phase 15 makes the checks automatic and the delivery repeatable: **every pull request is tested twice (offline in GitHub Actions, and against Snowflake in dbt Cloud) before it can merge, production rebuilds on a schedule, the documentation site republishes itself, and the warehouse has a spending cap.**

```
developer ──push branch──► pull request to main
                              │
          ┌───────────────────┼──────────────────────────────┐
          ▼                   ▼                              ▼
  GitHub Actions        GitHub Actions                 dbt Cloud "PR check"
  "Python tests"        "dbt parse and compile"        dbt build --select state:modified+
  38 unit + API tests   no Snowflake login,            in DBT_CLOUD_PR_<job>_<pr>_<LAYER>,
                        placeholder credentials        everything else deferred to Production
          └───────────────────┼──────────────────────────────┘
                              ▼
            ruleset protect_main: all three checks green → merge allowed
                              ▼
   main ──► GitHub Actions "docs": dbt docs → GitHub Pages
        ──► dbt Cloud "prod_build": dbt build, Mon/Wed/Fri 06:00 PST (14:00 UTC)
```

## Continuous integration: two layers

| Check | Where | What it catches | Cost |
|---|---|---|---|
| `Python tests` | GitHub Actions ([ci.yml](../.github/workflows/ci.yml)) | Broken ingestion, landing or API code (38 tests) | Free (public repo) |
| `dbt parse and compile` | GitHub Actions | Bad Jinja, refs, YAML, sources, test definitions; renders every non-incremental model's SQL | Free, no Snowflake |
| `dbt Cloud` | dbt Cloud CI job `PR check` | SQL that compiles but fails in Snowflake, failing data tests, broken downstream models | Only the changed models and their children |

The offline layer runs first and is fast. It cannot find a wrong column name or a failing test, because it never talks to Snowflake. The dbt Cloud layer can, but it costs warehouse time and counts against the plan, so it builds only `state:modified+`: the changed models plus everything downstream, reading unchanged parents from the latest Production run (deferral).

The two incremental models are excluded from offline compile: an incremental model asks the warehouse whether its table exists, which needs a live connection.

## Isolation: CI never touches the real tables

[generate_schema_name.sql](../dbt_retailflow/macros/generate_schema_name.sql) decides where each model is built:

| Build | target.schema | Result |
|---|---|---|
| Production and normal development | `STAGING` | `STAGING`, `SILVER`, `DATA_QUALITY`, `GOLD` (unchanged) |
| dbt Cloud CI for PR 17 | `dbt_cloud_pr_70506183146280_17` | `DBT_CLOUD_PR_70506183146280_17_DATA_QUALITY`, ... |
| Any build with `RETAILFLOW_SCHEMA_PREFIX=DEV_SAAD` | `STAGING` | `DEV_SAAD_SILVER`, `DEV_SAAD_GOLD`, ... |

Sources (BRONZE, AUDIT, CONTROL) are read-only and never prefixed. `RETAIL_DBT_ROLE` needs `CREATE SCHEMA` on the database ([grant_dbt_ci.sql](../sql/snowflake/00_setup/grant_dbt_ci.sql)); dbt Cloud drops the PR schemas when the pull request closes.

## Continuous delivery

| What | How | When |
|---|---|---|
| Production data | dbt Cloud deploy job `prod_build` in environment `Production` (profile `retailflow_prod`, role `RETAIL_DBT_ROLE`, warehouse `RETAILFLOW_WH`; the run log reports target `default`, which nothing in the project depends on): `dbt build`, generate docs | Cron `0 14 * * 1,3,5`, plus on demand (for example `python -m landing scan --trigger-dbt`) |
| Documentation site | [docs.yml](../.github/workflows/docs.yml): `dbt parse`, `dbt docs generate --no-compile --empty-catalog --static`, deploy to GitHub Pages | Every push to `main` that touches `dbt_retailflow/` |
| Branch protection | Ruleset `protect_main`: PR required (0 approvals, one developer), the three checks above required, no deletion, no force push | Always |

dbt Cloud cron is in UTC. 14:00 UTC is 06:00 PST, 07:00 PDT in summer.

## Plan limits

dbt Cloud Developer (free): one seat, one project, **3,000 successful models built per month** across all jobs; jobs stop for the rest of the month at the cap. The project has 98 models.

| Job | Models per run | Runs per month | Models per month |
|---|---|---|---|
| `prod_build` | 98 | about 13 | about 1,300 |
| `PR check` | changed models + children (1 for PR 17) | per PR | tens |

A daily full build would use about 2,940 and leave nothing for CI, which is why production runs three times a week.

## Cost review (2026-11-16)

[cost.sql](../sql/snowflake/05_validation/cost.sql) queries 1-8, run as ACCOUNTADMIN.

| Finding | Evidence | Action |
|---|---|---|
| 5.9 credits billed in about 10 days | METERING_DAILY_HISTORY | None, about USD 12-24 of trial credit |
| COMPUTE_WH (3.95) cost more than the project warehouse (2.43) | WAREHOUSE_METERING_HISTORY | |
| COMPUTE_WH is the Snowsight worksheets: 3,500+ queries, about 3 minutes of execution | Query 8 | Almost all of its credits were idle time |
| COMPUTE_WH and SNOWFLAKE_LEARNING_WH suspended after 300 s | SHOW WAREHOUSES | `AUTO_SUSPEND = 60` |
| RETAILFLOW_WH: X-Small, 60 s, dbt 5,582 queries in 14 minutes, slowest model about 2 s | Queries 4-5 | No tuning needed |
| Storage about 30 MB | TABLE_STORAGE_METRICS | Negligible |
| No spending cap | | Resource monitor `RETAILFLOW_MONTHLY`, 20 credits per month, notify at 75 %, suspend at 100 % |

The changes are in [cost_guardrails.sql](../sql/snowflake/00_setup/cost_guardrails.sql). Expected run rate with CI and three production builds a week: about 2-3 credits a month. The cap is about seven times that, so it only stops a runaway job or a forgotten warehouse.

## Files

| Path | Purpose |
|---|---|
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | Python tests, dbt parse and compile on every PR and push to `main` |
| [.github/workflows/docs.yml](../.github/workflows/docs.yml) | dbt docs to GitHub Pages |
| [macros/generate_schema_name.sql](../dbt_retailflow/macros/generate_schema_name.sql) | CI and prefix isolation |
| [00_setup/grant_dbt_ci.sql](../sql/snowflake/00_setup/grant_dbt_ci.sql) | `CREATE SCHEMA` for dbt, leftover schema query |
| [00_setup/cost_guardrails.sql](../sql/snowflake/00_setup/cost_guardrails.sql) | Auto-suspend and resource monitor |
| [05_validation/cost.sql](../sql/snowflake/05_validation/cost.sql) | Cost review queries |
| `dbt_retailflow/models/monitoring/mon_file_feeds.sql` | Gained `last_attempt_at` and `last_attempt_status` (the first change shipped through the full pipeline) |

## Definition of done

A pull request runs all three checks and cannot merge unless they pass. The dbt Cloud check builds only the change, in its own schema. Production builds on a schedule without anyone starting it. The documentation site updates on merge. The cost review is written down with guardrails in the repository.

## Outcome (2026-11-17)

| Check | Result |
|---|---|
| GitHub Actions CI | Green on PRs #14-#17 and on every push to `main` |
| Docs site | Published on each merge to `main` (last run for PR #17, success) |
| Production job | `prod_build` run by hand, success. Then triggered by its schedule at 12:37 PST, success |
| dbt Cloud CI | PR #17: GitHub Pull Request trigger, deferred to Production run 70506184244109, schema overridden to `dbt_cloud_pr_70506183146280_17`, `dbt build --select state:modified+` in 13 s, check green on GitHub |
| Isolation | `DBT_CLOUD_PR_70506183146280_17_DATA_QUALITY` created with the new columns; real `DATA_QUALITY` unchanged until merge |
| New columns | `retailco_products` last loaded 17:50, last attempt 17:58 SKIPPED (the Phase 14 redelivery), now visible in monitoring |
| Branch protection | Ruleset `protect_main` active: deletion and force push blocked, PR required, checks `Python tests`, `dbt parse and compile`, `dbt Cloud` required |
| Repository connection | dbt Cloud project moved from a plain git clone to the dbt GitHub app, which is what lets PRs trigger CI |
