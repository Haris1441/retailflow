with source_records as (
    {{ bronze_source('BIGQUERY', 'order_items') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:order_item_id::string) as order_item_id,
    try_to_number(raw_payload:order_id::string) as order_id,
    try_to_number(raw_payload:product_id::string) as product_id,
    try_to_number(raw_payload:quantity::string) as quantity,
    try_to_decimal(raw_payload:unit_price::string, 18, 4) as unit_price,
    try_to_decimal(raw_payload:discount_amount::string, 18, 4) as discount_amount,
    try_to_decimal(raw_payload:tax_amount::string, 18, 4) as tax_amount,
    try_to_decimal(raw_payload:line_total::string, 18, 4) as line_total,
    try_to_timestamp_tz(raw_payload:created_at::string) as line_created_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as line_updated_at
from source_records
