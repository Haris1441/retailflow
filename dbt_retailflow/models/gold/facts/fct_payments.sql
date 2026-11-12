-- FCT_PAYMENTS: one validated payment attempt or refund event of a PUBLISHABLE order.
-- Cash is converted at the UTC payment date. payment_type CHARGE collects cash, REFUND returns it.
with fx as (
    select rate_date, from_currency, exchange_rate
    from {{ ref('silver_exchange_rates') }}
    where to_currency = 'USD'
),

payments as (
    select
        p.*,
        o.store_id,
        o.customer_key,
        coalesce(p.payment_type, 'CHARGE') as payment_kind,
        {{ utc_date('p.payment_at') }} as payment_date
    from {{ ref('silver_payments') }} as p
    join {{ ref('silver_order_publication') }} as pub
      on pub.order_key = p.order_key
     and pub.publication_status = 'PUBLISHABLE'
    join {{ ref('silver_orders') }} as o
      on o.order_key = p.order_key
)

select
    p.payment_key,
    p.source_system,
    p.payment_id,
    p.order_key,
    p.customer_key,
    coalesce(p.store_id, -1) as store_sk,
    {{ date_key('p.payment_date') }} as payment_date_key,
    p.payment_at,
    p.payment_method,
    p.payment_status,
    p.payment_kind as payment_type,
    p.payment_status = 'SUCCESS' as is_successful,
    p.return_id,
    p.payment_currency,
    p.payment_amount as payment_amount_local,
    iff(p.payment_currency = 'USD', 1, fx.exchange_rate) as usd_rate,
    iff(p.payment_currency = 'USD', 1, fx.exchange_rate) is not null as has_usd,
    p.payment_amount * iff(p.payment_currency = 'USD', 1, fx.exchange_rate) as payment_amount_usd
from payments as p
left join fx
  on fx.from_currency = p.payment_currency
 and fx.rate_date = p.payment_date
