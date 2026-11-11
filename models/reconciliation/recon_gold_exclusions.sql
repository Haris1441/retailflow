-- Exclusion register: every current Silver record that Gold does not publish, with the reason.
-- Orders that are not PUBLISHABLE (HELD or QUARANTINED, Phase 9) take their lines, payments and
-- returns with them. Each row points to the quarantine evidence through order_key.
with publication as (
    select order_key, publication_status, hold_reason
    from {{ ref('silver_order_publication') }}
)

select 'orders' as entity, o.order_key as record_key, o.order_key, o.source_system,
       p.publication_status, p.hold_reason as exclusion_reason
from {{ ref('silver_orders') }} as o
join publication as p on p.order_key = o.order_key
where p.publication_status <> 'PUBLISHABLE'

union all

select 'order_lines', i.order_item_key, i.order_key, i.source_system,
       coalesce(p.publication_status, 'NO_ORDER'), coalesce(p.hold_reason, 'Order has no publication status')
from {{ ref('silver_order_items') }} as i
left join publication as p on p.order_key = i.order_key
where coalesce(p.publication_status, 'NO_ORDER') <> 'PUBLISHABLE'

union all

select 'payments', y.payment_key, y.order_key, y.source_system,
       coalesce(p.publication_status, 'NO_ORDER'), coalesce(p.hold_reason, 'Order has no publication status')
from {{ ref('silver_payments') }} as y
left join publication as p on p.order_key = y.order_key
where coalesce(p.publication_status, 'NO_ORDER') <> 'PUBLISHABLE'

union all

select 'returns', 'BIGQUERY:' || r.return_id::varchar, r.order_key, 'BIGQUERY',
       coalesce(p.publication_status, 'NO_ORDER'), coalesce(p.hold_reason, 'Order has no publication status')
from {{ ref('silver_returns') }} as r
left join publication as p on p.order_key = r.order_key
where coalesce(p.publication_status, 'NO_ORDER') <> 'PUBLISHABLE'
