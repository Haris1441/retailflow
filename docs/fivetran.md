# Fivetran comparison · build vs buy

The Python loader from Phases 5–6 moves BigQuery data into `BRONZE.SOURCE_RECORDS`. This optional track runs **Fivetran**, a managed ingestion service, against the same BigQuery baseline, then reconciles the two landing areas row by row. The point is not to replace Python. It is to show, with evidence, what a managed connector gives you and what it takes away.

The Fivetran path is **independent of dbt**. Fivetran writes physical tables into its own schema, and the reconciliation reads those tables and Bronze directly with SQL. No dbt models, grants or builds are involved, and the dbt project stays exactly as Phase 7 left it.

```
BigQuery retailflow_source ─┬─► Python loader ─► BRONZE.SOURCE_RECORDS            (raw JSON, one table) ─┐
                            └─► Fivetran      ─► FIVETRAN_BQQ_RETAILFLOW_SOURCE.*  (typed physical tables) ┴─► fivetran_vs_bronze.sql
```

Scope is four baseline tables: `customers`, `orders`, `order_items` and `payments`. Both paths carry the fixture's `source_record_id`, so every row can be matched one to one.

| File | Purpose |
|---|---|
| [grant_fivetran.sql](../sql/snowflake/00_setup/grant_fivetran.sql) | Fivetran role and key-pair SERVICE user. Can create its own schema only. |
| [fivetran_vs_bronze.sql](../sql/snowflake/05_validation/fivetran_vs_bronze.sql) | Row, total, field, load-time and column-shape comparison between the Fivetran tables and Bronze. |

## Before you start

- **Account.** Sign up for Fivetran with a work-appropriate account. Check the current free-plan and trial limits on Fivetran's pricing page. Four tables of about 96,000 rows is a small initial sync, but limits change.
- **BigQuery Sandbox.** Fivetran's BigQuery connector runs queries and may create helper tables in a working dataset. Sandbox has no billing and expires tables after 60 days. If connector setup fails on permissions or billing, Sandbox limits are the most likely cause. Upgrading the project to billing (still free within the BigQuery free tier) usually resolves it.
- **Credits.** Fivetran writes through `RETAILFLOW_WH`, which auto-suspends after 60 seconds. Pause the connector when you finish so scheduled syncs do not keep waking the warehouse.

## 1. Snowflake: key pair and Fivetran user

Snowflake is retiring single-factor passwords for service logins, so Fivetran connects with a key pair. Create it in **Git Bash** in a folder outside the repository:

```bash
mkdir -p ~/.fivetran && cd ~/.fivetran
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out fivetran_rsa_key.p8 -nocrypt
openssl rsa -in fivetran_rsa_key.p8 -pubout -out fivetran_rsa_key.pub
```

Open `fivetran_rsa_key.pub`, copy the text between the BEGIN and END lines as one line, and paste it in place of `PASTE_PUBLIC_KEY_BODY_HERE` in [grant_fivetran.sql](../sql/snowflake/00_setup/grant_fivetran.sql). Run the script in Snowsight as `ACCOUNTADMIN`. Do not save the edited script back into the repository. The private key (`.p8`) never goes into Snowflake, Git or chat.

## 2. Fivetran: add the Snowflake destination

In Fivetran, add a **Snowflake** destination:

| Field | Value |
|---|---|
| Host | `QREFHIF-KF84029.snowflakecomputing.com` |
| Port | `443` |
| User | `FIVETRAN_USER` |
| Database | `RETAIL_DWH` |
| Role | `FIVETRAN_ROLE` |
| Auth | Key pair. Paste the contents of `fivetran_rsa_key.p8`. |

Run **Save & Test**. A default-warehouse error means the user has no default warehouse. Run `ALTER USER FIVETRAN_USER SET DEFAULT_WAREHOUSE = RETAILFLOW_WH;` and test again.

## 3. Fivetran: add the BigQuery connection

1. Add a **Google BigQuery** connection and name it **`fivetran_bqq`**. The name becomes the schema prefix, so the tables land in `FIVETRAN_BQQ_RETAILFLOW_SOURCE`, and it cannot be changed later. A different name means replacing `FIVETRAN_BQQ_RETAILFLOW_SOURCE` in `fivetran_vs_bronze.sql`.
2. Choose Fivetran's service account. The setup form shows its email address.
3. In Google Cloud, grant that email these roles. Each one was needed during setup on 2026-11-09/10:

   | Role | Scope | Why |
   |---|---|---|
   | BigQuery Job User | project `bq-dbt-sf` | Run queries |
   | BigQuery Read Session User | project `bq-dbt-sf` | Read tables through the Storage Read API (`bigquery.readsessions.create`) |
   | BigQuery Data Viewer | dataset `retailflow_source` | Read the source tables |
   | BigQuery Data Editor | dataset `fivetran_working` only | Create the helper tables Fivetran uses to detect changes (`bigquery.tables.create`) |

   Create the `fivetran_working` dataset in the same location as `retailflow_source` (US) and enter it as the connection's **working dataset**. The source dataset stays read-only to Fivetran.
4. Select the `retailflow_source` dataset and, in the schema tab, keep only `customers`, `orders`, `order_items` and `payments`. Keep Fivetran's default naming.
5. Start the initial sync and wait for it to finish.

## 4. Check what Fivetran landed

In Snowsight, as `ACCOUNTADMIN`:

```sql
SHOW TABLES IN SCHEMA RETAIL_DWH.FIVETRAN_BQQ_RETAILFLOW_SOURCE;
SELECT * FROM RETAIL_DWH.FIVETRAN_BQQ_RETAILFLOW_SOURCE.ORDERS LIMIT 5;
```

Expect four physical tables owned by `FIVETRAN_ROLE`, with the BigQuery columns plus Fivetran metadata such as `_FIVETRAN_SYNCED`. `ACCOUNTADMIN` can read them because `FIVETRAN_ROLE` is granted to `SYSADMIN`.

## 5. Reconcile

Run [fivetran_vs_bronze.sql](../sql/snowflake/05_validation/fivetran_vs_bronze.sql) in Snowsight.

| Check | Expected |
|---|---|
| Rows per entity | customers 5,000 · orders 20,000 · order_items 50,000 · payments 20,800, all matched, zero only-in-one-side |
| Money totals | difference 0 for order, line and payment amounts |
| Field differences | no rows |
| Load times | Fivetran `_FIVETRAN_SYNCED` vs Bronze `INGESTED_AT`, for your notes |
| Column shape | Fivetran's typed columns and metadata vs Bronze's raw JSON and provenance |

A difference is a finding, not a failure. Record what caused it, for example a type mapping, decimal scale or time zone.

Then **pause the connector** in Fivetran.

## 6. Write the build-vs-buy notes

Fill in this table in the learning journal from what you observed:

| Question | Python loader | Fivetran |
|---|---|---|
| Time to first load | Phases 5–6 of code and tests | |
| Landing shape | One table, raw JSON in VARIANT, full provenance | |
| Duplicate deliveries kept as evidence? | Yes, by physical identity | |
| Availability vs effective time | Both carried | |
| Deletes | Explicit tombstone events | |
| Watermark control and replay | CONTROL tables, overlap window | |
| Schema changes | New fields land in JSON, typed later in dbt | |
| Cost driver | Your warehouse time | |
| Who fixes it when it breaks | You | |
