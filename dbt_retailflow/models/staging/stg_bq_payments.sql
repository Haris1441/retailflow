with source_records as (
    {{ bronze_source('BIGQUERY', 'payments') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:payment_id::string) as payment_id,
    try_to_number(raw_payload:order_id::string) as order_id,
    upper(trim(raw_payload:payment_method::string)) as payment_method,
    upper(trim(raw_payload:payment_status::string)) as payment_status,
    upper(trim(raw_payload:payment_type::string)) as payment_type,
    try_to_decimal(raw_payload:payment_amount::string, 18, 4) as payment_amount,
    upper(trim(raw_payload:payment_currency::string)) as payment_currency,
    try_to_timestamp_tz(raw_payload:payment_timestamp::string) as payment_at,
    nullif(trim(raw_payload:transaction_reference::string), '') as transaction_reference,
    try_to_timestamp_tz(raw_payload:updated_at::string) as payment_updated_at,
    try_to_number(raw_payload:return_id::string) as return_id
from source_records
