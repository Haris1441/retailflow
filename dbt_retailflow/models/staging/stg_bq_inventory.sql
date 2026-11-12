with source_records as (
    {{ bronze_source('BIGQUERY', 'inventory') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_effective_at, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    nullif(trim(raw_payload:inventory_id::string), '') as inventory_id,
    try_to_number(raw_payload:store_id::string) as store_id,
    try_to_number(raw_payload:product_id::string) as product_id,
    try_to_date(raw_payload:snapshot_date::string) as snapshot_date,
    try_to_number(raw_payload:quantity_on_hand::string) as quantity_on_hand,
    try_to_number(raw_payload:reserved_quantity::string) as reserved_quantity,
    try_to_number(raw_payload:reorder_level::string) as reorder_level,
    try_to_timestamp_tz(raw_payload:updated_at::string) as inventory_updated_at
from source_records
