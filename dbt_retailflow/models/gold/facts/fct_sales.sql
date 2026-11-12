-- FCT_SALES: one validated order line of a PUBLISHABLE order, with historical dimension keys.
--
-- Merchandise (business_rules.md):
--   gross_merchandise   = quantity * unit_price
--   booked_merchandise  = gross - line discount - allocated order discount   (tax and shipping excluded)
-- The header order discount is allocated to lines in proportion to positive line net value,
-- rounded to 2 decimals; the rounding remainder goes to the first eligible line by line id.
-- Recognition: fulfilled, not canceled, pending or deleted, on the UTC fulfillment date.
-- USD uses the resolved rate for the event date (fulfillment date, else order date); a missing
-- rate leaves USD null and has_usd false. Cost is the product cost at order time (USD).
with publishable_orders as (
    select o.*
    from {{ ref('silver_orders') }} as o
    join {{ ref('silver_order_publication') }} as p
      on p.order_key = o.order_key
    where p.publication_status = 'PUBLISHABLE'
),

lines as (
    select
        i.order_item_key,
        i.order_item_id,
        i.order_key,
        o.source_system,
        o.order_id,
        o.customer_key,
        o.store_id,
        o.order_at,
        o.fulfilled_at,
        o.order_status,
        o.order_channel,
        o.currency,
        coalesce(o.discount_amount, 0) as order_discount_local,
        coalesce(o.is_deleted, false) as order_is_deleted,
        i.product_id,
        i.quantity,
        i.unit_price,
        i.quantity * i.unit_price as gross_merchandise_local,
        coalesce(i.discount_amount, 0) as line_discount_local,
        coalesce(i.tax_amount, 0) as line_tax_local,
        i.quantity * i.unit_price - coalesce(i.discount_amount, 0) as line_net_local
    from {{ ref('silver_order_items') }} as i
    join publishable_orders as o
      on o.order_key = i.order_key
),

allocation_base as (
    select
        lines.*,
        sum(iff(line_net_local > 0, line_net_local, 0)) over (partition by order_key) as eligible_net_local,
        row_number() over (
            partition by order_key
            order by iff(line_net_local > 0, 0, 1), try_to_number(order_item_id), order_item_id
        ) as allocation_seq
    from lines
),

allocation_rounded as (
    select
        allocation_base.*,
        iff(line_net_local > 0 and eligible_net_local > 0,
            round(order_discount_local * line_net_local / eligible_net_local, 2),
            0) as allocation_rounded_local
    from allocation_base
),

allocated as (
    select
        allocation_rounded.*,
        allocation_rounded_local
          + iff(allocation_seq = 1,
                order_discount_local - sum(allocation_rounded_local) over (partition by order_key),
                0) as allocated_order_discount_local
    from allocation_rounded
),

fx as (
    select rate_date, from_currency, exchange_rate
    from {{ ref('silver_exchange_rates') }}
    where to_currency = 'USD'
),

enriched as (
    select
        a.*,
        a.line_net_local - a.allocated_order_discount_local as booked_merchandise_local,
        a.fulfilled_at is not null
          and a.order_status not in ('CANCELED', 'PENDING')
          and not a.order_is_deleted as is_recognized,
        {{ utc_date('a.order_at') }} as order_date,
        {{ utc_date('a.fulfilled_at') }} as fulfillment_date,
        iff(a.currency = 'USD', 1, fx.exchange_rate) as usd_rate,
        coalesce(c.customer_sk, 'UNKNOWN') as customer_sk,
        coalesce(p.product_sk, 'UNKNOWN') as product_sk,
        p.cost_price as unit_cost_usd
    from allocated as a
    left join fx
      on fx.from_currency = a.currency
     and fx.rate_date = {{ utc_date('coalesce(a.fulfilled_at, a.order_at)') }}
    left join {{ ref('dim_customer') }} as c
      on c.customer_key = a.customer_key
     and {{ as_of('c', 'a.order_at') }}
    left join {{ ref('dim_product') }} as p
      on p.product_id = a.product_id
     and {{ as_of('p', 'a.order_at') }}
)

select
    order_item_key,
    order_key,
    source_system,
    order_id,
    order_item_id,
    customer_sk,
    product_sk,
    coalesce(store_id, -1) as store_sk,
    {{ date_key('order_date') }} as order_date_key,
    {{ date_key('fulfillment_date') }} as fulfillment_date_key,
    order_at,
    fulfilled_at,
    order_status,
    order_channel,
    is_recognized,
    currency,
    quantity,
    unit_price,
    gross_merchandise_local,
    line_discount_local,
    allocated_order_discount_local,
    booked_merchandise_local,
    line_tax_local,
    usd_rate,
    usd_rate is not null as has_usd,
    booked_merchandise_local * usd_rate as booked_merchandise_usd,
    unit_cost_usd,
    quantity * unit_cost_usd as cost_usd
from enriched
