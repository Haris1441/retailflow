# Phase 11 · SCD Type 1, Type 2 and Type 3

Silver so far holds one current row per key: what is true **now**. Analytics also needs what was true **then**. Which loyalty tier did a customer have when they ordered? What price and category did a product have on the sale date? Phase 11 builds slowly changing dimensions for customers and products, showing the three classic types side by side.

| Type | Behaviour | Model |
|---|---|---|
| **1** | Overwrite. Only the latest value exists. | `silver_customers`, `silver_products` (unchanged since Phase 8) |
| **2** | New row per change, with `valid_from` / `valid_to` | `silver_customers_scd2`, `silver_products_scd2` |
| **3** | Current value plus one previous value in extra columns | `silver_customer_loyalty_scd3` |

## Type 2 built from version history, not snapshots

dbt snapshots record the current table on each run and stamp changes with **processing time**. They have three weaknesses here:
- **They can't rebuild the past.** History starts on the first snapshot run, and a missed run loses changes forever.
- **They put late changes at the wrong time.** Customer 12's loyalty change happened on 2025-01-13 but arrived on 2025-02-24. A snapshot would date it 2025-02-24 and attribute 42 days of orders to the wrong tier.
- **They can't be recreated from scratch.** A snapshot table is state you have to protect.

RetailFlow already keeps every trusted delivery with its business time, the `resolve_versions` output from Phases 8 to 10. So Type 2 here is a **pure function of Bronze**: drop it, rebuild it, and the result is identical, including late changes in the right place. The `scd2_history` macro:

1. Takes trusted versions only (not `DUPLICATE` or `REJECTED`) and orders them by business time.
2. Starts a new row only when a **tracked** (Type 2) column changes. Other changes don't create history.
3. Sets `valid_to` (exclusive) to the next row's `valid_from`. The open row has `valid_to` NULL and `is_current` true.
4. Restates **Type 1** columns: every row shows the latest trusted value. A corrected name is a fix, not history.
5. Closes the open row at a DELETE tombstone, and creates no row for the tombstone itself.

### Which columns are Type 1 and which are Type 2

| Entity | Type 2 (tracked) | Type 1 (restated) | Not tracked |
|---|---|---|---|
| Customers | email, status, loyalty tier, preferred language, country, city, address, postal code, is_deleted | first and last name, phone, gender, birth and registration date | nested addresses array, audit timestamps |
| Products | category, brand, supplier, base price, cost price, status | SKU, name, description, currency | audit timestamps |

This is a business decision, not a technical one. Track an attribute when reports must group facts by its historical value.

### What the fixtures produce

| Change | Batch | Effect on history |
|---|---|---|
| Customers 2–11 tier and address | BATCH_003 | Second row from 2025-02-17 |
| Customer 12 tier, **backdated** | BATCH_006 | Second row from 2025-01-13, arrived 42 days later |
| Customers 21, 22 email | BATCH_005 | Second row from 2025-02-21 (warnings, but accepted) |
| Customers 102–110 (even) preferred language | BATCH_007 | Second row from 2025-02-25 |
| Customers 101–109 (odd) addresses only | BATCH_007 | **No** new row, because the addresses array isn't tracked |
| Customer 111 soft delete | BATCH_008 | Second row from 2025-02-27, `is_deleted` true |
| Products 2–11 price and category | BATCH_003 | Second row from 2025-02-17 |
| Products 31–45 negative price, missing category | BATCH_005 | **No** row, because rejected changes never enter history |

Expected totals are 5,028 customer history rows (5,020 BigQuery + 8 API) for 5,009 customers, and 1,011 product rows for 1,001 products.

### Using it: point-in-time joins

```sql
JOIN silver_customers_scd2 h
  ON h.customer_key = o.customer_key
 AND (o.order_at >= h.valid_from OR h.version_number = 1)   -- the first row also covers earlier facts
 AND (o.order_at <  h.valid_to   OR h.valid_to IS NULL)
```

`valid_to` is exclusive, so a fact at the exact change instant matches exactly one row. The first row covers earlier facts because a baseline row's `valid_from` is the source `updated_at`, which can be later than older orders. Phase 12 Gold uses this join.

## Type 3

`silver_customer_loyalty_scd3` keeps `current_loyalty_tier`, `previous_loyalty_tier` and `loyalty_tier_since`. It answers "upgraded from what, and when?" without a history join. It keeps only one previous value: a second change overwrites the first. It is derived from Type 2, and periods created by other attribute changes are not counted as tier changes.

## Tests

- `history_key` is unique and not null. Every history key exists in the current Type 1 table.
- `assert_scd2_history_valid` checks four things:
  - every period is positive;
  - there are no gaps or overlaps between consecutive periods;
  - every current customer and product has exactly one current history row;
  - that row agrees with the Type 1 table.

## Run

1. In dbt Cloud, switch to `phase-11-scd` and pull, then run:
   ```text
   dbt build --select tag:staging tag:silver tag:data_quality
   ```
   No `--full-refresh` is needed: the new tables are created on first build, and the Phase 10 incremental tables simply process nothing new. Expect no errors and no warnings.
2. Run [scd.sql](../sql/snowflake/05_validation/scd.sql) and compare each result with the expected values in the comments.

## Files

| Path | Purpose |
|---|---|
| `macros/scd2_history.sql` | Builds Type 2 rows from trusted versions |
| `models/silver/history/silver_customers_scd2.sql` | Customer Type 2 with Type 1 restatement |
| `models/silver/history/silver_products_scd2.sql` | Product Type 2 |
| `models/silver/history/silver_customer_loyalty_scd3.sql` | Loyalty Type 3 |
| `models/silver/history/_history.yml` | Column tests |
| `tests/assert_scd2_history_valid.sql` | Period and consistency checks |
| [scd.sql](../sql/snowflake/05_validation/scd.sql) | Validation with expected values |

## Definition of done

The build passes with no warnings. The counts in scd.sql check 1 match, and the 19 customers and 10 products with history are exactly the expected ones. Customer 12 shows GOLD from 2025-01-13 despite arriving on 2025-02-24, products 31–45 have one row each, Type 3 shows 11 tier changes, and the point-in-time query shows orders whose historical tier differs from the current tier.

## Outcome (2026-11-11)

Every check in `scd.sql` matched.

| Check | Result |
|---|---|
| Customer history | BigQuery 5,020 rows for 5,001 keys (19 with history), API 8 rows, one current row per key |
| Product history | 1,011 rows for 1,001 keys, 10 with history |
| Keys with history | Exactly the expected 19 customers: 2–12, 21, 22, the five even IDs 102–110, and 111 |
| Late change | Customer 12: STANDARD 2025-01-01 to 2025-01-13, then GOLD; delivered in BATCH_006 on 2025-02-24, 42 days late |
| Rejected changes | Products 31–45 have one row each; products 2–11 have two |
| Type 3 | 5,009 customers, 11 with a tier change (customers 2–12) |
| Point in time | Customer 12 has 2 orders at STANDARD (before 2025-01-13) and 3 at GOLD. Every order for customers 2–11 was placed before their 2025-02-17 change, so all show the old tier while a Type 1 join would show the new one |

The point-in-time result is the business case for Type 2. Joined to the Type 1 customer table, all of customer 2's orders would be reported as SILVER, although the customer was GOLD when placing them.
