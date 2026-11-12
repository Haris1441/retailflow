with source_records as (
    {{ bronze_source('BIGQUERY', 'stores') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:store_id::string) as store_id,
    nullif(trim(raw_payload:store_name::string), '') as store_name,
    upper(trim(raw_payload:store_type::string)) as store_type,
    upper(trim(raw_payload:country::string)) as country,
    nullif(trim(raw_payload:region::string), '') as region,
    nullif(trim(raw_payload:city::string), '') as city,
    upper(trim(raw_payload:currency::string)) as currency,
    upper(trim(raw_payload:channel::string)) as channel,
    try_to_date(raw_payload:opening_date::string) as opening_date,
    upper(trim(raw_payload:status::string)) as store_status,
    try_to_timestamp_tz(raw_payload:updated_at::string) as store_updated_at
from source_records
