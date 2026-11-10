-- Publication status for every order key ever delivered. Gold publishes an order's facts
-- (header, lines, payments, promotions, returns) only when publication_status = 'PUBLISHABLE'.
--   QUARANTINED  the header has no trusted version (orders 10 and 30)
--   HELD         the header is trusted, but at least one of its lines is rejected (order 20)
--   DELETED      the header's current version is a delete tombstone
-- Children of QUARANTINED and HELD orders stay in Silver as valid records; Gold excludes them
-- and reconciles the exclusion separately (DATA_GENERATION_MANIFEST.md).
with order_keys as (
    select
        source_system,
        business_key as order_id,
        max(iff(disposition = 'ACCEPTED', 1, 0)) = 1 as has_trusted_header,
        max(iff(disposition = 'DELETED', 1, 0)) = 1 as is_deleted
    from {{ ref('silver_record_dispositions') }}
    where entity = 'orders'
    group by 1, 2
),

rejected_lines as (
    select
        'BIGQUERY' as source_system,
        order_id::varchar as order_id,
        count(*) as rejected_line_count
    from {{ ref('int_bq_order_items__versions') }}
    where version_rank = 1
      and disposition = 'REJECTED'
    group by 1, 2
)

select
    k.source_system || ':' || k.order_id as order_key,
    k.source_system,
    k.order_id,
    case
        when k.is_deleted then 'DELETED'
        when not k.has_trusted_header then 'QUARANTINED'
        when l.rejected_line_count > 0 then 'HELD'
        else 'PUBLISHABLE'
    end as publication_status,
    case
        when k.is_deleted then 'Order deleted at source'
        when not k.has_trusted_header then 'Order header rejected; see DATA_QUALITY.DQ_QUARANTINE'
        when l.rejected_line_count > 0 then l.rejected_line_count || ' order line(s) rejected'
    end as hold_reason
from order_keys as k
left join rejected_lines as l
  on l.source_system = k.source_system
 and l.order_id = k.order_id
