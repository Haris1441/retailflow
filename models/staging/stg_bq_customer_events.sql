with source_records as (
    {{ bronze_source('BIGQUERY', 'customer_events') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:event_id) as event_id,
    try_to_number(raw_payload:customer_id) as customer_id,
    try_to_timestamp_tz(raw_payload:event_timestamp::string) as event_at,
    lower(trim(raw_payload:event_type::string)) as event_type,
    raw_payload:event_payload as event_payload,
    nullif(trim(raw_payload:event_payload:session:session_id::string), '') as session_id,
    lower(trim(raw_payload:event_payload:device:device_type::string)) as device_type,
    lower(trim(raw_payload:event_payload:campaign:channel::string)) as campaign_channel,
    raw_payload:event_payload:products as products
from source_records
