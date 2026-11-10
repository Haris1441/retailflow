with source_records as (
    {{ bronze_source('BIGQUERY', 'customers') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:customer_id::string) as customer_id,
    nullif(trim(raw_payload:first_name::string), '') as first_name,
    nullif(trim(raw_payload:last_name::string), '') as last_name,
    nullif(lower(trim(raw_payload:email::string)), '') as email_normalized,
    nullif(trim(raw_payload:phone::string), '') as phone,
    raw_payload:gender::string as gender,
    nullif(trim(raw_payload:preferred_language::string), '') as preferred_language,
    raw_payload:addresses as addresses,
    try_to_date(raw_payload:birth_date::string) as birth_date,
    try_to_date(raw_payload:registration_date::string) as registration_date,
    upper(trim(raw_payload:customer_status::string)) as customer_status,
    upper(trim(raw_payload:loyalty_tier::string)) as loyalty_tier,
    upper(trim(raw_payload:country::string)) as country,
    nullif(trim(raw_payload:city::string), '') as city,
    nullif(trim(raw_payload:address::string), '') as address,
    nullif(trim(raw_payload:postal_code::string), '') as postal_code,
    try_to_timestamp_tz(raw_payload:created_at::string) as customer_created_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as customer_updated_at,
    coalesce(try_to_boolean(raw_payload:is_deleted::string), false) as is_deleted
from source_records
