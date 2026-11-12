-- KPIs by UTC calendar month: recognized merchandise, merchandise credits, net revenue,
-- gross margin, average order value and month-over-month growth.
--   Recognized merchandise and cost of goods sold   -> fulfillment month
--   Completed merchandise credits and cost reversal -> return completion month
--   Net revenue  = recognized merchandise - completed merchandise credits
--   Gross margin = net revenue - (cost sold - cost reversed); margin % only when net revenue > 0
--   AOV          = merchandise of orders with complete USD conversion / those orders
--   MoM growth   = (net - prior net) / prior net, only when prior net revenue > 0
with order_totals as (
    select
        order_key,
        date_trunc('month', {{ utc_date('min(fulfilled_at)') }}) as month_start,
        sum(booked_merchandise_usd) as merchandise_usd,
        sum(cost_usd) as cost_usd,
        booland_agg(has_usd) as has_complete_usd
    from {{ ref('fct_sales') }}
    where is_recognized
    group by order_key
),

sales as (
    select
        month_start,
        sum(merchandise_usd) as recognized_merchandise_usd,
        sum(cost_usd) as cost_of_goods_sold_usd,
        count(*) as recognized_orders,
        count_if(not has_complete_usd) as orders_missing_usd,
        sum(iff(has_complete_usd, merchandise_usd, 0)) as complete_order_merchandise_usd,
        count_if(has_complete_usd) as complete_orders
    from order_totals
    group by month_start
),

returns as (
    select
        date_trunc('month', {{ utc_date('completed_at') }}) as month_start,
        sum(merchandise_credit_usd) as merchandise_credits_usd,
        sum(cost_reversal_usd) as cost_reversal_usd,
        sum(return_quantity) as returned_units
    from {{ ref('fct_returns') }}
    where is_completed
    group by 1
),

monthly as (
    select
        coalesce(s.month_start, r.month_start) as month_start,
        coalesce(s.recognized_merchandise_usd, 0) as recognized_merchandise_usd,
        coalesce(r.merchandise_credits_usd, 0) as merchandise_credits_usd,
        coalesce(s.recognized_merchandise_usd, 0) - coalesce(r.merchandise_credits_usd, 0) as net_revenue_usd,
        coalesce(s.cost_of_goods_sold_usd, 0) - coalesce(r.cost_reversal_usd, 0) as net_cost_usd,
        coalesce(s.recognized_orders, 0) as recognized_orders,
        coalesce(s.orders_missing_usd, 0) as orders_missing_usd,
        coalesce(r.returned_units, 0) as returned_units,
        s.complete_order_merchandise_usd,
        s.complete_orders
    from sales as s
    full outer join returns as r
      on r.month_start = s.month_start
)

select
    {{ date_key('month_start') }} as month_date_key,
    to_char(month_start, 'YYYY-MM') as year_month,
    recognized_merchandise_usd,
    merchandise_credits_usd,
    net_revenue_usd,
    net_cost_usd,
    net_revenue_usd - net_cost_usd as gross_margin_usd,
    iff(net_revenue_usd > 0, (net_revenue_usd - net_cost_usd) / net_revenue_usd, null) as gross_margin_pct,
    recognized_orders,
    orders_missing_usd,
    returned_units,
    complete_order_merchandise_usd / nullif(complete_orders, 0) as average_order_value_usd,
    lag(net_revenue_usd) over (order by month_start) as prior_net_revenue_usd,
    iff(lag(net_revenue_usd) over (order by month_start) > 0,
        (net_revenue_usd - lag(net_revenue_usd) over (order by month_start))
          / lag(net_revenue_usd) over (order by month_start),
        null) as mom_net_revenue_growth
from monthly
