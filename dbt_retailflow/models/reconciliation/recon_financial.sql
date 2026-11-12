-- Layer 3b · Silver -> Gold, money. Per measure and currency (local amounts are only added within
-- one currency):   silver_amount = gold_amount + excluded_amount
--   LINE_MERCHANDISE  quantity * unit price - line discount, per order line
--   ORDER_DISCOUNT    header discount (Silver) vs allocated discount (Gold)
--   PAYMENTS          payment amount, per payment type
--   RETURN_CREDITS    merchandise credit
-- Lines whose order header is quarantined have no trusted currency. They report in their own
-- bucket, "UNRESOLVED <order_key>", so amounts in different currencies are never added together.
with exclusions as (
    select entity, record_key from {{ ref('recon_gold_exclusions') }}
),

line_merchandise as (
    select
        coalesce(o.currency, 'UNRESOLVED ' || i.order_key) as currency,
        i.quantity * i.unit_price - coalesce(i.discount_amount, 0) as silver_amount,
        iff(x.record_key is not null, i.quantity * i.unit_price - coalesce(i.discount_amount, 0), 0) as excluded_amount
    from {{ ref('silver_order_items') }} as i
    left join {{ ref('silver_orders') }} as o on o.order_key = i.order_key
    left join exclusions as x on x.entity = 'order_lines' and x.record_key = i.order_item_key
),

rows_ as (
    -- LINE_MERCHANDISE
    select 'LINE_MERCHANDISE' as measure, currency, silver_amount, 0 as gold_amount, excluded_amount
    from line_merchandise
    union all
    select 'LINE_MERCHANDISE', currency, 0, gross_merchandise_local - line_discount_local, 0
    from {{ ref('fct_sales') }}

    -- ORDER_DISCOUNT
    union all
    select 'ORDER_DISCOUNT', o.currency, coalesce(o.discount_amount, 0), 0,
           iff(x.record_key is not null, coalesce(o.discount_amount, 0), 0)
    from {{ ref('silver_orders') }} as o
    left join exclusions as x on x.entity = 'orders' and x.record_key = o.order_key
    union all
    select 'ORDER_DISCOUNT', currency, 0, allocated_order_discount_local, 0
    from {{ ref('fct_sales') }}

    -- PAYMENTS
    union all
    select 'PAYMENTS ' || coalesce(p.payment_type, 'CHARGE'), p.payment_currency, p.payment_amount, 0,
           iff(x.record_key is not null, p.payment_amount, 0)
    from {{ ref('silver_payments') }} as p
    left join exclusions as x on x.entity = 'payments' and x.record_key = p.payment_key
    union all
    select 'PAYMENTS ' || payment_type, payment_currency, 0, payment_amount_local, 0
    from {{ ref('fct_payments') }}

    -- RETURN_CREDITS
    union all
    select 'RETURN_CREDITS', coalesce(o.currency, 'UNRESOLVED ' || r.order_key), r.refund_amount, 0,
           iff(x.record_key is not null, r.refund_amount, 0)
    from {{ ref('silver_returns') }} as r
    left join {{ ref('silver_orders') }} as o on o.order_key = r.order_key
    left join exclusions as x on x.entity = 'returns' and x.record_key = 'BIGQUERY:' || r.return_id::varchar
    union all
    select 'RETURN_CREDITS', currency, 0, merchandise_credit_local, 0
    from {{ ref('fct_returns') }}
)

select
    measure,
    currency,
    sum(silver_amount) as silver_amount,
    sum(gold_amount) as gold_amount,
    sum(excluded_amount) as excluded_amount,
    sum(silver_amount) - sum(gold_amount) - sum(excluded_amount) as difference,
    iff(abs(sum(silver_amount) - sum(gold_amount) - sum(excluded_amount)) <= 0.005, 'PASS', 'FAIL') as status
from rows_
group by 1, 2
