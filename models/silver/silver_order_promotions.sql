-- Order-promotion bridge: one row per application of a promotion to an order.
select
    order_promotion_id,
    'BIGQUERY:' || order_id::varchar as order_key,
    order_id::varchar as order_id,
    promotion_id,
    applied_discount_amount,
    applied_at,
    order_promotion_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_order_promotions__versions') }}
where disposition = 'ACCEPTED'
