with source_records as (
    {{ bronze_source('BIGQUERY', 'categories') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_updated_at, source_available_at,
    ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:category_id::string) as category_id,
    nullif(trim(raw_payload:category_name::string), '') as category_name,
    try_to_number(raw_payload:parent_category_id::string) as parent_category_id,
    try_to_number(raw_payload:category_level::string) as category_level,
    coalesce(try_to_boolean(raw_payload:is_active::string), false) as is_active,
    try_to_timestamp_tz(raw_payload:updated_at::string) as category_updated_at
from source_records
