-- API only: one shipment per order (shipping object), keyed by shipment ID.
select
    'MOCK_API:' || shipping:shipment_id::string as shipment_key,
    'MOCK_API:' || order_id as order_key,
    source_system,
    shipping:shipment_id::string as shipment_id,
    upper(trim(shipping:method::string)) as shipping_method,
    try_to_decimal(shipping:amount::string, 18, 4) as shipping_amount,
    source_record_id,
    batch_id as source_batch_id
from {{ ref('int_api_orders__versions') }}
where disposition = 'ACCEPTED'
  and shipping is not null
