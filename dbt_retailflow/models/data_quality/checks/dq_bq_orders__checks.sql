-- REJECT checks for BigQuery order header deliveries.
-- Balance: header total = lines (line_total includes tax) - order discount + shipping, within 0.01.
-- Lines use each line's top-ranked version even when that line is itself rejected: a rejected
-- line (order 20, line 58) holds its order from publication but does not make the header wrong.
with versions as (
    select source_record_id, business_key, batch_id, order_id, customer_id,
           order_total, discount_amount, shipping_amount
    from {{ ref('stg_bq_orders') }}
    where source_operation <> 'DELETE'
),

current_customers as (
    select customer_id
    from {{ ref('int_bq_customers__versions') }}
    where disposition = 'ACCEPTED'
),

line_totals as (
    select order_id, sum(line_total) as lines_total
    from {{ ref('int_bq_order_items__versions') }}
    where version_rank = 1
      and disposition in ('ACCEPTED', 'REJECTED')
    group by order_id
),

failures as (
    select 'BIGQUERY' as source_system, 'orders' as entity, v.source_record_id, v.business_key, v.batch_id,
           'ORD_MISSING_CUSTOMER' as rule_id, 'REJECT' as severity,
           'customer_id=' || coalesce(v.customer_id::varchar, 'null') as observed_value
    from versions as v
    left join current_customers as c on c.customer_id = v.customer_id
    where c.customer_id is null

    union all

    select 'BIGQUERY', 'orders', v.source_record_id, v.business_key, v.batch_id,
           'ORD_AMOUNT_MISMATCH', 'REJECT',
           'header=' || coalesce(v.order_total::varchar, 'null')
             || ', expected='
             || (coalesce(l.lines_total, 0) - coalesce(v.discount_amount, 0) + coalesce(v.shipping_amount, 0))::varchar
    from versions as v
    left join line_totals as l on l.order_id = v.order_id
    where v.order_total is null
       or abs(v.order_total - (coalesce(l.lines_total, 0) - coalesce(v.discount_amount, 0)
                               + coalesce(v.shipping_amount, 0))) > 0.01
)

{{ dq_with_waivers() }}
