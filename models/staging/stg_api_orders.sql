with source_records as (
    {{ bronze_source('MOCK_API', 'orders') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    nullif(trim(raw_payload:order_id::string), '') as order_id,
    nullif(trim(raw_payload:customer_id::string), '') as customer_id,
    nullif(trim(raw_payload:store_id::string), '') as api_store_id,
    try_to_timestamp_tz(raw_payload:order_date::string) as order_at,
    try_to_timestamp_tz(raw_payload:fulfilled_at::string) as fulfilled_at,
    upper(trim(raw_payload:order_status::string)) as order_status,
    upper(trim(raw_payload:order_channel::string)) as order_channel,
    upper(trim(raw_payload:currency::string)) as currency,
    try_to_decimal(raw_payload:order_total::string, 18, 4) as order_total,
    try_to_decimal(raw_payload:discount_amount::string, 18, 4) as discount_amount,
    try_to_decimal(raw_payload:shipping_amount::string, 18, 4) as shipping_amount,
    try_to_decimal(raw_payload:tax_amount::string, 18, 4) as tax_amount,
    raw_payload:customer as customer,
    raw_payload:items as items,
    raw_payload:shipping as shipping,
    raw_payload:payments as payment_references
from source_records
