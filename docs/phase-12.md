# Phase 12 · Gold dimensional model and business metrics

Gold turns trusted Silver into a star schema that analysts can query safely, plus KPI tables that implement the definitions in [business_rules.md](business_rules.md). It publishes only orders that Phase 9 marked `PUBLISHABLE`. It joins every fact to the dimension version that was valid at the time of the event, using Phase 11 history.

```
                    DIM_DATE
                       │
DIM_CUSTOMER ──┐       │       ┌── DIM_PRODUCT
 (SCD2, as of  │       │       │   (SCD2, as of order time,
  order time)  ▼       ▼       ▼    category hierarchy, brand)
             FCT_SALES   FCT_RETURNS   FCT_PAYMENTS   FCT_INVENTORY_SNAPSHOT
                       ▲
                   DIM_STORE (market, channel)
                       │
   KPI marts: daily sales · monthly revenue · sales by segment · customer lifetime value · stockout
```

## Dimensions

| Model | Grain | Notes |
|---|---|---|
| `dim_date` | UTC date, 2024–2026 | Reporting uses UTC dates |
| `dim_customer` | Customer version (SCD2) | `customer_sk` = Phase 11 `history_key`; `UNKNOWN` member |
| `dim_product` | Product version (SCD2) | Category path (department > subcategory > category) and brand; `UNKNOWN` member |
| `dim_store` | Store | Market (country, currency) and channel; `-1` unknown member |

## Facts

| Model | Grain | Key rules |
|---|---|---|
| `fct_sales` | Order line of a PUBLISHABLE order | Booked merchandise = quantity × price − line discount − allocated order discount. Tax and shipping are excluded. Recognized when fulfilled and not canceled, pending or deleted. USD at the fulfillment-date rate. Cost at order time |
| `fct_returns` | Return line of a published sale | Merchandise credit at the completion-date rate; cost reversal uses the sale's unit cost |
| `fct_payments` | Payment attempt or refund of a PUBLISHABLE order | CHARGE collects cash, REFUND returns it, both at the payment-date rate |
| `fct_inventory_snapshot` | Store, product, date | Available = on hand − reserved; stockout when 0 |

**Discount allocation.** The header order discount is spread over lines in proportion to their positive net value and rounded to cents. The rounding remainder goes to the first eligible line by line ID, so line amounts always add up to the header exactly.

**Point-in-time keys.** `fct_sales` stores `customer_sk` and `product_sk` for the versions valid at `order_at`. The `as_of` macro adds one rule: the first version also covers earlier events, so every line finds exactly one row. Sales by loyalty tier and by category therefore use the tier and category at purchase. For example, customer 12's orders before 2025-01-13 count as STANDARD and later ones as GOLD.

**Exclusions.** Orders 10 and 30 (quarantined) and order 20 (held) are not in any fact. Their lines, payments and returns stay in Silver. Phase 13 reconciles Silver to Gold and explains each exclusion.

## KPI marts

| Model | KPIs |
|---|---|
| `gold_daily_sales` | Daily sales (UTC fulfillment day), USD conversion coverage |
| `gold_monthly_revenue` | Recognized merchandise, merchandise credits, net revenue, gross margin and margin %, AOV, month-over-month growth |
| `gold_sales_by_segment_month` | Sales by historical category, by loyalty tier at order time, by country, by channel, and by country and channel |
| `gold_customer_lifetime_value` | CLV (recognized merchandise less linked credits) and purchase frequency per identified customer |
| `gold_inventory_stockout_daily` | Stockout rate per snapshot date and market |

Top 10 products, return rate and refund rate are simple queries over the facts (see `gold.sql`). Not built in this phase:
- **Conversion funnel and promotion effectiveness:** these need an activity fact and a promotion bridge.
- **Freshness and reliability:** this belongs to Phase 14 monitoring.

## Expected results

The expected values in [gold.sql](../sql/snowflake/05_validation/gold.sql) were **recomputed independently** in Python from the fixture generation rules: prices, currencies, rates, statuses, change batches and exclusions. They were not read back from Gold. Two independent implementations agreeing to the cent is much stronger evidence than a query that checks itself. Headline numbers:

| Measure | Expected |
|---|---|
| Recognized orders | 20,598 BigQuery + 8 API |
| Recognized merchandise | USD 9,669,722.83 BigQuery + 160.00 API |
| Net revenue | Jan 9,171,538.24 · Feb 445,185.23 |
| Gross margin | 40.59 % · 40.71 % |
| Return rate | 501 / 94,108 units = 0.53 % |

## Tests

- Keys are unique and not null. Every fact key relates to its dimension, including dates.
- `assert_gold_sales_balance` checks three things:
  - every line of a PUBLISHABLE order is in `fct_sales`, and no other line is;
  - allocated discounts add up to each header discount exactly;
  - booked merchandise per order equals header total − shipping − tax, within one cent.

## Run

1. In Snowsight, run [grant_dbt_gold.sql](../sql/snowflake/00_setup/grant_dbt_gold.sql) as `ACCOUNTADMIN`. It grants USAGE, CREATE TABLE and CREATE VIEW on GOLD to `RETAIL_DBT_ROLE`.
2. In dbt Cloud, switch to `phase-12-gold` and pull, then run:
   ```text
   dbt build --select tag:staging tag:silver tag:data_quality tag:gold
   ```
   Expect no errors and no warnings.
3. Run [gold.sql](../sql/snowflake/05_validation/gold.sql) and compare each result with its expected values.

## Files

| Path | Purpose |
|---|---|
| `macros/gold_helpers.sql` | `utc_date`, `date_key`, `as_of` point-in-time join |
| `models/gold/dimensions/*` | Date, customer, product, store |
| `models/gold/facts/*` | Sales, returns, payments, inventory snapshots |
| `models/gold/marts/*` | KPI tables |
| `models/gold/_gold.yml` | Key and relationship tests |
| `tests/assert_gold_sales_balance.sql` | Silver-to-Gold line and amount balance |
| [grant_dbt_gold.sql](../sql/snowflake/00_setup/grant_dbt_gold.sql) | GOLD grants |
| [gold.sql](../sql/snowflake/05_validation/gold.sql) | Validation with independently computed expectations |

## Definition of done

The build passes with no warnings, and every check in `gold.sql` matches its expected value to the cent.

## Outcome (2026-11-11)

Every check in `gold.sql` matched the independent Python recomputation **to the cent**:

| Check | Result |
|---|---|
| Row counts | All 8 tables as expected (fct_sales 52,110, fct_payments 22,906, ...) |
| Recognized sales | BigQuery 20,598 orders, 48,096 lines, 94,092 units, USD 9,669,722.83, cost 5,743,849.80; API 8 orders, USD 160.00 |
| Coverage | 0 unknown customers, 0 unknown products, 0 lines missing USD |
| Local currency | AED 9,244,588.13 · GBP 1,880,921.68 · PKR 651,332,244.00 · USD 2,495,393.65 |
| Monthly | Jan net 9,171,538.24, margin 40.59 %, AOV 517.47 · Feb net 445,185.23, margin 40.71 %, MoM −95.15 % |
| Daily | 30 + 3 sales days, adding up exactly to the monthly totals |
| Segments | All 3 categories, 4 tier buckets and 12 country-channel cells |
| Top 10 and CLV | Identical ranking and values; 4,864 customers |
| Rates | Return 501 / 94,108 = 0.00532367 · refund 25.48 / 10,178,600.89 · stockout 742 / 8,408 = 0.08824929 |
| Point in time | Customer 12: two STANDARD orders before 2025-01-13, three GOLD after |

February's −95 % MoM is a fixture artefact, not a defect. The baseline orders span January, and February holds only the late BATCH_002/003 fulfillments.
