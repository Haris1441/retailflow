-- Phase 12: FCT_SALES must reconcile with Silver. Expect zero rows.
--   1. Every line of a PUBLISHABLE order is in FCT_SALES, and no other line is.
--   2. Allocated order discount per order equals the header discount exactly.
--   3. Booked merchandise per order equals header total - shipping - tax (within 0.01),
--      the merchandise part of the Phase 9 header balance.
with expected_lines as (
    select i.order_item_key
    from {{ ref('silver_order_items') }} as i
    join {{ ref('silver_order_publication') }} as p
      on p.order_key = i.order_key
    where p.publication_status = 'PUBLISHABLE'
),

line_errors as (
    select coalesce(e.order_item_key, s.order_item_key) as problem_key,
           iff(s.order_item_key is null, 'missing from fct_sales', 'not publishable but in fct_sales') as problem
    from expected_lines as e
    full outer join {{ ref('fct_sales') }} as s
      on s.order_item_key = e.order_item_key
    where e.order_item_key is null or s.order_item_key is null
),

order_sums as (
    select order_key,
           sum(allocated_order_discount_local) as allocated_discount,
           sum(booked_merchandise_local) as booked_merchandise
    from {{ ref('fct_sales') }}
    group by order_key
),

order_errors as (
    select o.order_key,
           'allocated discount ' || s.allocated_discount::varchar || ' <> header ' || coalesce(o.discount_amount, 0)::varchar
    from order_sums as s
    join {{ ref('silver_orders') }} as o on o.order_key = s.order_key
    where s.allocated_discount <> coalesce(o.discount_amount, 0)
    union all
    select o.order_key,
           'booked ' || s.booked_merchandise::varchar || ' <> header merchandise '
             || (o.order_total - coalesce(o.shipping_amount, 0) - coalesce(o.tax_amount, 0))::varchar
    from order_sums as s
    join {{ ref('silver_orders') }} as o on o.order_key = s.order_key
    where abs(s.booked_merchandise - (o.order_total - coalesce(o.shipping_amount, 0) - coalesce(o.tax_amount, 0))) > 0.01
)

select * from line_errors
union all
select * from order_errors
