-- KPI: customer lifetime value per identified customer (natural key, all versions together):
-- lifetime recognized USD merchandise less completed merchandise credits linked to the customer,
-- plus purchase frequency. Unknown customers are excluded.
with sales as (
    select
        c.customer_key,
        count(distinct s.order_key) as fulfilled_orders,
        sum(s.booked_merchandise_usd) as recognized_merchandise_usd,
        min(s.order_at) as first_order_at,
        max(s.order_at) as last_order_at
    from {{ ref('fct_sales') }} as s
    join {{ ref('dim_customer') }} as c on c.customer_sk = s.customer_sk
    where s.is_recognized
      and c.customer_key <> 'UNKNOWN'
    group by 1
),

credits as (
    select c.customer_key, sum(r.merchandise_credit_usd) as merchandise_credits_usd
    from {{ ref('fct_returns') }} as r
    join {{ ref('dim_customer') }} as c on c.customer_sk = r.customer_sk
    where r.is_completed
    group by 1
)

select
    s.customer_key,
    cur.source_system,
    cur.customer_id,
    cur.loyalty_tier as current_loyalty_tier,
    s.fulfilled_orders,
    s.recognized_merchandise_usd,
    coalesce(cr.merchandise_credits_usd, 0) as merchandise_credits_usd,
    s.recognized_merchandise_usd - coalesce(cr.merchandise_credits_usd, 0) as lifetime_value_usd,
    s.first_order_at,
    s.last_order_at
from sales as s
left join credits as cr on cr.customer_key = s.customer_key
left join {{ ref('dim_customer') }} as cur
  on cur.customer_key = s.customer_key
 and cur.is_current
