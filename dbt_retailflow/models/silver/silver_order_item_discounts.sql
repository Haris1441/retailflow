-- API only: one row per discount applied to an order line (key: order line + discount ID).
-- Flattened independently of shipping and payments so sibling arrays never multiply.
select
    'MOCK_API:' || i.value:order_item_id::string || ':' || d.value:discount_id::string as order_item_discount_key,
    'MOCK_API:' || i.value:order_item_id::string as order_item_key,
    'MOCK_API:' || o.order_id as order_key,
    o.source_system,
    d.value:discount_id::string as discount_id,
    try_to_decimal(d.value:amount::string, 18, 4) as discount_amount,
    o.source_record_id,
    o.batch_id as source_batch_id
from {{ ref('int_api_orders__versions') }} as o,
lateral flatten(input => o.items) as i,
lateral flatten(input => i.value:discounts) as d
where o.disposition = 'ACCEPTED'
