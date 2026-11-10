with source_records as (
    {{ bronze_source('BIGQUERY', 'brands') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:brand_id::string) as brand_id,
    nullif(trim(raw_payload:brand_name::string), '') as brand_name,
    upper(trim(raw_payload:origin_country::string)) as origin_country,
    upper(trim(raw_payload:status::string)) as brand_status,
    try_to_timestamp_tz(raw_payload:created_at::string) as brand_created_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as brand_updated_at
from source_records
