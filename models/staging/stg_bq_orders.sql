with source_records as (
    {{ bronze_source('BIGQUERY', 'orders') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:order_id::string) as order_id,
    try_to_number(raw_payload:customer_id::string) as customer_id,
    try_to_number(raw_payload:store_id::string) as store_id,
    try_to_timestamp_tz(raw_payload:order_date::string) as order_at,
    upper(trim(raw_payload:order_status::string)) as order_status,
    upper(trim(raw_payload:order_channel::string)) as order_channel,
    upper(trim(raw_payload:currency::string)) as currency,
    try_to_decimal(raw_payload:order_total::string, 18, 4) as order_total,
    try_to_decimal(raw_payload:discount_amount::string, 18, 4) as discount_amount,
    try_to_decimal(raw_payload:shipping_amount::string, 18, 4) as shipping_amount,
    try_to_decimal(raw_payload:tax_amount::string, 18, 4) as tax_amount,
    try_to_timestamp_tz(raw_payload:created_at::string) as order_created_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as order_updated_at,
    try_to_timestamp_tz(raw_payload:fulfilled_at::string) as fulfilled_at,
    coalesce(try_to_boolean(raw_payload:is_deleted::string), false) as is_deleted
from source_records
