-- Recognized USD merchandise by fulfillment month for the commercial segments in
-- business_rules.md, in one long table (segment_type, segment_value):
--   CATEGORY       historical product category at order time (department > subcategory > category)
--   LOYALTY_TIER   customer loyalty tier at order time (NO_TIER for API customers)
--   COUNTRY        store market
--   CHANNEL        order channel
--   COUNTRY_CHANNEL store market and order channel
-- Point-in-time dimension rows come from the SCD Type 2 keys stored on FCT_SALES.
with sales as (
    select
        to_char(d.month_start, 'YYYY-MM') as year_month,
        s.order_key,
        s.quantity,
        s.booked_merchandise_usd,
        p.department_name || ' > ' || p.subcategory_name || ' > ' || p.category_name as category_path,
        coalesce(c.loyalty_tier, 'NO_TIER') as loyalty_tier,
        st.country,
        s.order_channel
    from {{ ref('fct_sales') }} as s
    join {{ ref('dim_date') }} as d on d.date_key = s.fulfillment_date_key
    join {{ ref('dim_product') }} as p on p.product_sk = s.product_sk
    join {{ ref('dim_customer') }} as c on c.customer_sk = s.customer_sk
    join {{ ref('dim_store') }} as st on st.store_sk = s.store_sk
    where s.is_recognized
),

segments as (
    select year_month, 'CATEGORY' as segment_type, category_path as segment_value, order_key, quantity, booked_merchandise_usd from sales
    union all
    select year_month, 'LOYALTY_TIER', loyalty_tier, order_key, quantity, booked_merchandise_usd from sales
    union all
    select year_month, 'COUNTRY', country, order_key, quantity, booked_merchandise_usd from sales
    union all
    select year_month, 'CHANNEL', order_channel, order_key, quantity, booked_merchandise_usd from sales
    union all
    select year_month, 'COUNTRY_CHANNEL', country || ' ' || order_channel, order_key, quantity, booked_merchandise_usd from sales
)

select
    year_month,
    segment_type,
    segment_value,
    count(distinct order_key) as recognized_orders,
    sum(quantity) as units_sold,
    sum(booked_merchandise_usd) as recognized_merchandise_usd
from segments
group by 1, 2, 3
