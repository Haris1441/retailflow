# Source-to-target mapping

BigQuery owns the 15 source tables below. The independent API owns its orders, customers, payments, events and inventory. Use (source_system, business_id) for source-local keys and explicit crosswalks for shared products and stores. A customer email is a contact attribute. Any future cross-source identity stitching requires a governed match.

All rows land in Bronze with the original payload and a stable physical source record ID. Fixture changes have a batch ID, operation, source availability time and an effective time when applicable. Preserve source event time and source update time independently. Where a reference table lacks updated_at, use fixture availability for incremental extraction. A retry reuses the same physical identity. Two physical records with identical payload can both land, then count as a duplicate disposition in Silver. Business history uses the change identity and effective ordering. Conflicting records tied at the same authoritative sequence go to review.

| BigQuery source and business key | Silver contract | Gold consumers |
| --- | --- | --- |
| customers · customer_id | Customer state and change history. Trim names, normalize email and country, preserve raw values. Keep soft-delete state. Flatten addresses separately by customer and address ID | DIM_CUSTOMER |
| products · product_id | Product state and change history. Validate category, SKU, prices and currency. Preserve price and cost revisions | DIM_PRODUCT, FCT_SALES |
| categories · category_id | Resolve ancestors and path. Detect missing parents and cycles before flattening | DIM_CATEGORY |
| brands · brand_id | Normalize name, origin country and status | DIM_PRODUCT |
| suppliers · supplier_id | Normalize status and country. Validate lead time | DIM_PRODUCT enrichment |
| stores · store_id | Resolve market, channel and store status | DIM_STORE, DIM_CHANNEL |
| orders · order_id | Typed order header, customer/store keys, amounts, status and UTC lifecycle timestamps | FCT_SALES, FCT_ORDER_FULFILLMENT |
| order_items · order_item_id | Line quantity, unit price, discounts, tax and calculated line total. Join by order ID | FCT_SALES |
| payments · payment_id | One attempt or refund event. Normalize method, status, currency and transaction reference | FCT_PAYMENTS, DIM_PAYMENT_METHOD |
| inventory · store_id, product_id, snapshot_date | One resolved daily snapshot. Preserve quantity on hand, reserved and reorder threshold | FCT_INVENTORY_SNAPSHOT |
| returns · return_id | One return line. Validate original order, line and product plus cumulative quantities | FCT_RETURNS |
| promotions · promotion_id | Promotion definition, validity period, discount basis and status | DIM_PROMOTION |
| order_promotions · order_promotion_id | One application with order, promotion and applied amount | Order-promotion bridge |
| exchange_rates · rate_date, from_currency, to_currency | One resolved rate per pair and date. Retain correction history by effective_at and source sequence | USD conversion |
| customer_events · event_id | Event parent with session, device and campaign attributes. Extract repeating product attributes into an event child | FCT_CUSTOMER_ACTIVITY |

API order headers map to orders. Item arrays map to order lines by order and line ID. Line discounts use order, line and discount ID. Shipping maps by order and shipment ID. Payment detail maps by the API payment ID. The payments endpoint is authoritative for payment events. Order payload metadata can enrich the same event after identity matching. Count parents before and after flattening. Test each child key and join independently to avoid multiplying sibling arrays.

Customer tier and region, and product category and brand, are Type 2 attributes. Use surrogate keys and UTC intervals [valid_from, valid_to). Join the sales fact at order time. Customer name corrections are Type 1. Keep an optional previous-tier projection for Type 3 practice. Gold keys include a governed unknown dimension member for optional relationships and historical lookup gaps. Missing mandatory links route to quarantine.

## Phase 2 fixture contract

Use BigQuery Sandbox CTAS with a configurable fixed base date. Initial targets are 5,000 customer profiles, 1,000 products, 20,000 orders and 50,000 lines. Use reproducible IDs, a dedicated dataset, exact NUMERIC amounts, UTC timestamps, and repeatable references across all 15 tables. Include interconnected starter defects with documented expected counts. Phase 3 extends the defect matrix, nested payloads and change batches. Add fulfillment timestamps to the order fixture contract and use application IDs for the promotion bridge. Use synthetic USD, PKR, GBP and AED rates with explicit direction to USD. The batch manifest will capture fixture version, expected counts, seeded defects and disposition.
