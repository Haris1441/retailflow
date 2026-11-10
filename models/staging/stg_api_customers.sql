with source_records as (
    {{ bronze_source('MOCK_API', 'customers') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    nullif(trim(raw_payload:customer_id::string), '') as customer_id,
    nullif(lower(trim(raw_payload:email::string)), '') as email_normalized,
    try_to_timestamp_tz(raw_payload:created_at::string) as customer_created_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as customer_updated_at
from source_records
