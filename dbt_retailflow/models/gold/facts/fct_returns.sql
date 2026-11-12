-- FCT_RETURNS: one validated return line, joined to its sale in FCT_SALES (so returns of held or
-- quarantined orders are excluded). refund_amount is the merchandise credit in the fixtures; cash
-- refunds live in FCT_PAYMENTS. The credit converts at the completion date; the cost reversal uses
-- the unit cost recorded on the original sale (cost at order time).
with fx as (
    select rate_date, from_currency, exchange_rate
    from {{ ref('silver_exchange_rates') }}
    where to_currency = 'USD'
),

returns as (
    select
        r.*,
        s.customer_sk,
        s.product_sk,
        s.store_sk,
        s.order_channel,
        s.currency,
        s.unit_cost_usd,
        {{ utc_date('r.completed_at') }} as completion_date,
        {{ utc_date('r.requested_at') }} as request_date
    from {{ ref('silver_returns') }} as r
    join {{ ref('fct_sales') }} as s
      on s.order_item_key = r.order_item_key
)

select
    'BIGQUERY:' || r.return_id::varchar as return_key,
    r.return_id,
    r.order_key,
    r.order_item_key,
    r.customer_sk,
    r.product_sk,
    r.store_sk,
    {{ date_key('r.request_date') }} as request_date_key,
    {{ date_key('r.completion_date') }} as completion_date_key,
    r.requested_at,
    r.completed_at,
    r.return_status,
    r.return_reason,
    r.return_status = 'COMPLETED' and r.completed_at is not null as is_completed,
    r.order_channel,
    r.currency,
    r.return_quantity,
    r.refund_amount as merchandise_credit_local,
    iff(r.currency = 'USD', 1, fx.exchange_rate) as usd_rate,
    iff(r.currency = 'USD', 1, fx.exchange_rate) is not null as has_usd,
    r.refund_amount * iff(r.currency = 'USD', 1, fx.exchange_rate) as merchandise_credit_usd,
    r.return_quantity * r.unit_cost_usd as cost_reversal_usd
from returns as r
left join fx
  on fx.from_currency = r.currency
 and fx.rate_date = r.completion_date
