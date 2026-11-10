with source_records as (
    {{ bronze_source('BIGQUERY', 'suppliers') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:supplier_id::string) as supplier_id,
    nullif(trim(raw_payload:supplier_name::string), '') as supplier_name,
    nullif(lower(trim(raw_payload:contact_email::string)), '') as contact_email,
    upper(trim(raw_payload:country::string)) as country,
    try_to_number(raw_payload:lead_time_days::string) as lead_time_days,
    upper(trim(raw_payload:supplier_status::string)) as supplier_status
from source_records
