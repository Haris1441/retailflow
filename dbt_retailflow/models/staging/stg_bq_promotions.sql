with source_records as (
    {{ bronze_source('BIGQUERY', 'promotions') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:promotion_id::string) as promotion_id,
    nullif(trim(raw_payload:promotion_name::string), '') as promotion_name,
    upper(trim(raw_payload:promotion_type::string)) as promotion_type,
    try_to_decimal(raw_payload:discount_value::string, 18, 4) as discount_value,
    try_to_date(raw_payload:start_date::string) as start_date,
    try_to_date(raw_payload:end_date::string) as end_date,
    upper(trim(raw_payload:status::string)) as promotion_status,
    try_to_timestamp_tz(raw_payload:updated_at::string) as promotion_updated_at
from source_records
