-- One current row per return line. Return 60002 (99 units, BATCH_005) is current here and
-- becomes a quantity-rule rejection in Phase 9.
select
    return_id,
    'BIGQUERY:' || order_id::varchar as order_key,
    'BIGQUERY:' || order_item_id::varchar as order_item_key,
    order_id::varchar as order_id,
    order_item_id::varchar as order_item_id,
    product_id,
    return_quantity,
    return_reason,
    return_status,
    refund_amount,
    requested_at,
    completed_at,
    return_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_returns__versions') }}
where disposition = 'ACCEPTED'
