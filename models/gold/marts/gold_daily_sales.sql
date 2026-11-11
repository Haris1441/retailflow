-- KPI: daily sales. UTC fulfillment day, recognized USD merchandise after discounts.
-- lines_missing_usd reports conversion coverage (those lines are excluded from the USD sum).
select
    s.fulfillment_date_key as date_key,
    d.date_day as fulfillment_date,
    count(distinct s.order_key) as recognized_orders,
    count(*) as recognized_lines,
    sum(s.quantity) as units_sold,
    sum(s.booked_merchandise_usd) as recognized_merchandise_usd,
    count_if(not s.has_usd) as lines_missing_usd
from {{ ref('fct_sales') }} as s
join {{ ref('dim_date') }} as d
  on d.date_key = s.fulfillment_date_key
where s.is_recognized
group by 1, 2
