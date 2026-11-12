with source_records as (
    {{ bronze_source('BIGQUERY', 'exchange_rates') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_date(raw_payload:rate_date::string) as rate_date,
    upper(trim(raw_payload:from_currency::string)) as from_currency,
    upper(trim(raw_payload:to_currency::string)) as to_currency,
    try_to_decimal(raw_payload:exchange_rate::string, 18, 8) as exchange_rate,
    try_to_timestamp_tz(raw_payload:effective_at::string) as rate_effective_at
from source_records
