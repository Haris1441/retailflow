with source_records as (
    {{ bronze_source('MOCK_API', 'payments') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    nullif(trim(raw_payload:payment_id::string), '') as payment_id,
    nullif(trim(raw_payload:order_id::string), '') as order_id,
    upper(trim(raw_payload:payment_method::string)) as payment_method,
    upper(trim(raw_payload:payment_status::string)) as payment_status,
    try_to_decimal(raw_payload:payment_amount::string, 18, 4) as payment_amount,
    upper(trim(raw_payload:payment_currency::string)) as payment_currency,
    try_to_timestamp_tz(raw_payload:payment_timestamp::string) as payment_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as payment_updated_at
from source_records
