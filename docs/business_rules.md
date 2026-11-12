# Business requirements and metric glossary

Commerce needs to measure product and channel performance, finance needs to reconcile merchandise, cash and refunds, operations needs stock and fulfillment visibility, and engineering needs freshness and traceable recovery. Use these definitions for Gold acceptance.

## Financial rules

Use the store market and the order channel for commercial reporting. Daily reporting uses UTC dates for the learning environment. Use decimal amounts, keep transaction currency, and convert each event using the resolved event-date rate to USD. USD uses rate 1. Missing non-USD rates leave USD amounts null and appear in conversion coverage. Reports show excluded row counts. Aggregate local amounts only within each currency.

Gross merchandise is quantity times unit price. Subtract line discounts and the allocated order-level merchandise discount to calculate booked merchandise value. The header order discount is defined as an additional order-level amount. The applied promotion bridge explains that amount. Allocate proportionally to positive eligible line net values and assign the rounding remainder by stable line ID. Reconcile header total to merchandise after discounts plus tax and shipping. Payment receipts and refunds have their own event dates and cash measures.

Recognize merchandise when fulfilled using the fulfillment date. Include fulfilled orders that later enter a returned state. Exclude canceled, deleted and unfulfilled orders from recognized sales. Net revenue subtracts completed return merchandise credits on the completion date. Preserve the original sale and record the reversal separately. Cash refunds can differ from merchandise credits because cash can include tax or shipping. Source return refund_amount represents merchandise credit in the learning fixtures. Use payments for cash refunds. Track cost at order time for sold and returned units. Production finance would approve recognition timing, market calendars, rounding and FX policy.

## Gold facts

| Fact | Grain |
| --- | --- |
| FCT_SALES | One validated order line in its resolved state, with order ID and historical dimension keys |
| FCT_PAYMENTS | One validated payment attempt or refund event |
| FCT_RETURNS | One validated return line |
| FCT_INVENTORY_SNAPSHOT | One product, store and snapshot date |
| FCT_ORDER_FULFILLMENT | One order and its resolved fulfillment milestones |
| FCT_CUSTOMER_ACTIVITY | One event with session and optional customer keys |

Conformed dimensions cover customer, product, category, store, date, promotion, channel and payment method. Where facts need to be combined, aggregate each to the shared grain before joining or union compatible financial events.

## KPI acceptance definitions

| KPI | Grain and calculation |
| --- | --- |
| Daily sales | UTC fulfillment day. Sum recognized USD merchandise after discounts |
| Monthly net revenue | UTC calendar month. Recognized merchandise less completed merchandise credits, each on its event date |
| Sales by country | Store market and fulfillment period. Sum recognized merchandise |
| Sales by product category | Historical category at purchase and fulfillment period. Sum recognized merchandise |
| Top 10 products | Product in the selected fulfillment period, ranked by recognized merchandise with product ID tie-break |
| Customer lifetime value | Identified customer as of cutoff. Lifetime recognized merchandise less completed linked merchandise credits |
| Average order value | Fulfillment period. Recognized merchandise divided by distinct fulfilled orders with complete USD conversion |
| Return rate | Fulfilled order cohort. Completed returned units through cutoff divided by originally fulfilled units |
| Refund rate | Receipt order cohort. Successful cash refunds through cutoff divided by successful collected cash. Compare USD amounts using each event date |
| Stockout rate | Store-product snapshot period. Count snapshots with on-hand minus reserved equal to zero divided by valid observed snapshots |
| Customer purchase frequency | Identified customer and order-date period. Count distinct fulfilled orders |
| Repeat customer rate | Order-date period. Identified purchasers with at least two fulfilled orders in the period divided by identified purchasers |
| Conversion funnel | Session start period. Count sessions reaching each ordered stage from product view through cart, checkout and purchase. Divide by product-view sessions |
| Revenue by channel | Order channel and fulfillment period. Sum recognized merchandise |
| Month-over-month growth | Net revenue for adjacent calendar months. Difference divided by prior month when prior net revenue is positive |
| Sales by loyalty tier | Tier as of order time and fulfillment period. Sum recognized merchandise |
| Fulfillment time | Fulfillment period. Average elapsed hours from order creation to fulfillment, one observation per order |
| Gross margin | Recognition or return-completion period. Net revenue less sold merchandise cost plus cost reversal for returned units. Divide by net revenue for margin percent when positive |
| Promotion effectiveness | Promotion and fulfillment period. Report attributed recognized merchandise, applied discount and distinct orders. Allocate across promotions by discount share for additive revenue. Treat comparisons as descriptive |
| Freshness and reliability | Source entity and run window. Report last successful watermark, lag against freshness SLA, and successful terminal runs divided by terminal runs |

Empty denominators return null. Exclude quarantined rows throughout. Report missing FX coverage for USD monetary metrics and exclude incomplete orders from amount ratios that compare complete order totals. Exclude unidentified customers from customer-rate denominators.

## Quality and reconciliation

Missing or malformed email is a warning on an identifiable customer. Negative price, zero or negative quantity, missing mandatory references, invalid monetary balances beyond one minor unit, category cycles and impossible return quantities are rejection candidates. Keep missing product descriptions as warnings. Deduplicate by the defined grain and distinguish record replay from deliberate source duplicates. Do not publish critical integrity failures.

For each fixed source window, reconcile source, extracted and Bronze counts by physical identity. At Silver, assign each physical row one terminal disposition for that window, such as accepted, superseded version, duplicate or rejected. Store multiple rule results separately. Match financial totals at the relevant grain and currency, and explain exclusions. Track replay attempts without adding a new business result.
