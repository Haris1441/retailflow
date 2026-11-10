with source_records as (
    {{ bronze_source('BIGQUERY', 'returns') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:return_id::string) as return_id,
    try_to_number(raw_payload:order_id::string) as order_id,
    try_to_number(raw_payload:order_item_id::string) as order_item_id,
    try_to_number(raw_payload:product_id::string) as product_id,
    try_to_number(raw_payload:return_quantity::string) as return_quantity,
    upper(trim(raw_payload:return_reason::string)) as return_reason,
    upper(trim(raw_payload:return_status::string)) as return_status,
    try_to_decimal(raw_payload:refund_amount::string, 18, 4) as refund_amount,
    try_to_timestamp_tz(raw_payload:requested_at::string) as requested_at,
    try_to_timestamp_tz(raw_payload:completed_at::string) as completed_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as return_updated_at
from source_records
