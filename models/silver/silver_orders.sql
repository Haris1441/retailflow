-- One current order header per source system (key: source_system:order_id).
-- API store IDs map to BigQuery store keys through the api_crosswalk seed; the original
-- source value stays in source_store_id.
with bigquery as (
    select
        'BIGQUERY:' || order_id::varchar as order_key,
        source_system,
        order_id::varchar as order_id,
        'BIGQUERY:' || customer_id::varchar as customer_key,
        customer_id::varchar as customer_id,
        store_id,
        store_id::varchar as source_store_id,
        order_at,
        order_status,
        order_channel,
        currency,
        order_total,
        discount_amount,
        shipping_amount,
        tax_amount,
        order_created_at,
        order_updated_at,
        fulfilled_at,
        is_deleted,
        {{ silver_lineage() }}
    from {{ ref('int_bq_orders__versions') }}
    where disposition = 'ACCEPTED'
),

api as (
    select
        'MOCK_API:' || o.order_id as order_key,
        o.source_system,
        o.order_id,
        'MOCK_API:' || o.customer_id as customer_key,
        o.customer_id,
        x.target_id as store_id,
        o.api_store_id as source_store_id,
        o.order_at,
        o.order_status,
        o.order_channel,
        o.currency,
        o.order_total,
        o.discount_amount,
        o.shipping_amount,
        o.tax_amount,
        o.order_at as order_created_at,
        o.source_updated_at as order_updated_at,
        o.fulfilled_at,
        false as is_deleted,
        o.source_record_id,
        o.batch_id as source_batch_id,
        o.version_effective_at,
        o.version_count,
        o.has_version_tie
    from {{ ref('int_api_orders__versions') }} as o
    left join {{ ref('api_crosswalk') }} as x
      on x.source_system = o.source_system
     and x.entity = 'store'
     and x.source_id = o.api_store_id
    where o.disposition = 'ACCEPTED'
)

select * from bigquery
union all
select * from api
