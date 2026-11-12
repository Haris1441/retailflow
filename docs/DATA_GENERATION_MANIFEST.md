# Data generation manifest

## BATCH_001 · Initial BigQuery source

Default base date 2025-01-01. All fixture rows carry BATCH_001, an INSERT operation, a deterministic table-scoped physical ID and source availability at midnight UTC on base date plus 42 days. Use order, payment, return and event timestamps for business timing. FX rates are simulated. No CSVs or external data are required.

| Table | Source rows |
| --- | ---: |
| categories | 9 |
| brands | 25 |
| suppliers | 20 |
| stores | 12 |
| customers | 5,000 |
| products | 1,000 |
| promotions | 3 |
| exchange_rates | 168 |
| order_items | 50,000 |
| orders | 20,000 |
| order_promotions | 2,000 |
| payments | 20,800 |
| inventory | 8,400 |
| returns | 500 |
| customer_events | 12,000 |
| **Total** | **119,937** |

| Rule | Selection | Count | Expected disposition |
| --- | --- | ---: | --- |
| Missing customer email | customer_id divisible by 50 | 100 | Warning, retain customer |
| Malformed customer email | customer_id remainder 1 modulo 100 | 50 | Warning, retain customer |
| Missing product description | product_id divisible by 100 | 10 | Warning, retain product |
| Missing supplier contact | supplier_id 20 | 1 | Warning, retain supplier |
| Missing customer reference | order_id 10 uses customer_id 999999 | 1 | Quarantine order |
| Header amount mismatch | order_id 30 adds 7 local currency units | 1 | Quarantine order |
| Nonpositive order quantity | order_id 20, order_item_id 58, quantity 0 with retained original amounts | 1 | Quarantine line, hold order from publication |

No intended duplicate business keys. Some orders intentionally have distinct line IDs with the same product. Payment attempts have separate payment IDs. Pending and failed payment attempts and valid stockouts are ordinary observations. There are 18,000 completed, 1,000 canceled and 1,000 pending orders. Return credits in this batch are linked to fulfilled orders without order-level promotion discounts, which isolates line-level credit validation.

Expected Bronze count is 119,937 on initial ingestion. The three direct critical source rows and 161 warning rows are disjoint. Gold eligibility also depends on parent and child integrity. Suppress facts that depend on quarantined orders 10 and 30 or the invalid line on order 20, and reconcile dependency exclusions separately. A rerun with the same batch identity adds zero fixture rows and should add zero Bronze records once ingestion is implemented. No previous source rows are updated by this batch.

## BATCH_002–008 · Immutable change fixtures

| Batch | Physical rows | Expected incremental result |
| --- | ---: | --- |
| BATCH_002 | 6,070 | Accept one customer, one product, 2,000 orders, 2,000 lines, 2,000 payments and 68 simulated rates. Header, line and successful payment agree for every new order. |
| BATCH_003 | 1,020 | Accept 10 customer updates, 10 product updates, 500 pending-to-completed orders and 500 successful payment updates. No additional order keys. Customer loyalty and product category create history. |
| BATCH_004 | 4 | Accept cancellation for order 10040, fail its pending payment, and insert one completed merchandise return and matching successful cash refund for order 4. The refund and credit use separate ledgers. |
| BATCH_005 | 260 | Suppress 240 duplicate baseline events. Accept two customer updates with warnings. Quarantine 18 faulty changes and preserve prior trusted versions where available. |
| BATCH_006 | 302 | Accept 100 backdated orders, 100 lines, 100 payments, one backdated loyalty change and one corrected PKR-to-USD rate. The order payloads are 45 days older than their availability date. |
| BATCH_007 | 20 | Accept 10 customers with two addresses each and 10 events with a new device OS field. Five customers have a preferred language. Parent keys remain unchanged. |
| BATCH_008 | 2 | Accept one soft-delete update for customer 111 and one explicit hard-delete tombstone for event 401. The delete-only projection has 11,999 events. |
| **Total** | **7,678** | **7,420 accepted change rows, including two warnings, plus 240 duplicates and 18 direct quarantines.** |

### Defect keys in BATCH_005

| Scenario | Key | Count | Disposition |
| --- | --- | ---: | --- |
| Duplicate event | 240 baseline events with IDs in 1–288 delivered with new physical IDs | 240 | Duplicate, keep the same logical event |
| Blank email | Customer 21 | 1 | Warning, normalize to null |
| Shared email | Customer 22 reuses customer 2's email | 1 | Warning, retain both customer identities |
| Negative base price | Products 31–40 | 10 | Quarantine change |
| Missing category | Products 41–45 reference 999999 | 5 | Quarantine change |
| Category cycle | Category 1 becomes child of 7, forming 1 → 7 → 4 → 1 | 1 | Quarantine change |
| Negative stock | Store 1, product 1, first snapshot date | 1 | Quarantine change |
| Excessive return quantity | Return 60002 requests 99 units from the original order line | 1 | Quarantine change |

This reconciliation describes change rows only. It does not add accepted changes to the baseline count to estimate current state because updates replace state, deletes remove state, and some updates add versions. Replaying the same physical IDs should produce zero additional Bronze writes once ingestion exists. Silver dispositions are expected outcomes for later phases.
