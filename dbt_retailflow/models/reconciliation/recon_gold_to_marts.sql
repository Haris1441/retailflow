-- Layer 4 · Gold facts -> KPI marts. Every mart that reports recognized merchandise or credits in
-- USD must add up to the fact tables (within one cent of rounding).
with facts as (
    select
        (select sum(booked_merchandise_usd) from {{ ref('fct_sales') }} where is_recognized) as recognized_usd,
        (select sum(s.booked_merchandise_usd)
           from {{ ref('fct_sales') }} as s
          where s.is_recognized and s.customer_sk <> 'UNKNOWN') as identified_recognized_usd,
        (select sum(merchandise_credit_usd) from {{ ref('fct_returns') }} where is_completed) as credits_usd
),

checks as (
    select 'gold_daily_sales.recognized_merchandise_usd' as mart_measure, f.recognized_usd as fact_value,
           (select sum(recognized_merchandise_usd) from {{ ref('gold_daily_sales') }}) as mart_value
    from facts as f
    union all
    select 'gold_monthly_revenue.recognized_merchandise_usd', f.recognized_usd,
           (select sum(recognized_merchandise_usd) from {{ ref('gold_monthly_revenue') }})
    from facts as f
    union all
    select 'gold_monthly_revenue.merchandise_credits_usd', f.credits_usd,
           (select sum(merchandise_credits_usd) from {{ ref('gold_monthly_revenue') }})
    from facts as f
    union all
    select 'gold_customer_lifetime_value.recognized_merchandise_usd', f.identified_recognized_usd,
           (select sum(recognized_merchandise_usd) from {{ ref('gold_customer_lifetime_value') }})
    from facts as f
    union all
    select 'gold_sales_by_segment_month[' || s.segment_type || ']', max(f.recognized_usd), sum(s.recognized_merchandise_usd)
    from {{ ref('gold_sales_by_segment_month') }} as s
    cross join facts as f
    group by s.segment_type
)

select
    mart_measure,
    fact_value,
    mart_value,
    mart_value - fact_value as difference,
    iff(abs(coalesce(mart_value, 0) - coalesce(fact_value, 0)) <= 0.01, 'PASS', 'FAIL') as status
from checks
