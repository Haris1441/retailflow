with source_records as (
    {{ bronze_source('BIGQUERY', 'order_promotions') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:order_promotion_id::string) as order_promotion_id,
    try_to_number(raw_payload:order_id::string) as order_id,
    try_to_number(raw_payload:promotion_id::string) as promotion_id,
    try_to_decimal(raw_payload:applied_discount_amount::string, 18, 4) as applied_discount_amount,
    try_to_timestamp_tz(raw_payload:applied_at::string) as applied_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as order_promotion_updated_at
from source_records
