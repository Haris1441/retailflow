with source_records as (
    {{ bronze_source('BIGQUERY', 'products') }}
)
select
    source_record_id, business_key, batch_id, source_operation, source_updated_at,
    source_available_at, ingested_at, run_id, record_hash, raw_payload,
    try_to_number(raw_payload:product_id::string) as product_id,
    nullif(trim(raw_payload:sku::string), '') as sku,
    nullif(trim(raw_payload:product_name::string), '') as product_name,
    nullif(trim(raw_payload:description::string), '') as description,
    try_to_number(raw_payload:category_id::string) as category_id,
    try_to_number(raw_payload:brand_id::string) as brand_id,
    try_to_number(raw_payload:supplier_id::string) as supplier_id,
    try_to_decimal(raw_payload:base_price::string, 18, 4) as base_price,
    try_to_decimal(raw_payload:cost_price::string, 18, 4) as cost_price,
    upper(trim(raw_payload:currency::string)) as currency,
    upper(trim(raw_payload:product_status::string)) as product_status,
    try_to_timestamp_tz(raw_payload:created_at::string) as product_created_at,
    try_to_timestamp_tz(raw_payload:updated_at::string) as product_updated_at
from source_records
