-- One current order line per source system (key: source_system:order_item_id).
-- BigQuery lines are their own entity. API lines are flattened from the current order's
-- items array, so they change only when their order header changes.
with bigquery as (
    select
        'BIGQUERY:' || order_item_id::varchar as order_item_key,
        source_system,
        order_item_id::varchar as order_item_id,
        'BIGQUERY:' || order_id::varchar as order_key,
        order_id::varchar as order_id,
        product_id,
        product_id::varchar as source_product_id,
        quantity,
        unit_price,
        discount_amount,
        tax_amount,
        line_total,
        line_created_at,
        line_updated_at,
        {{ silver_lineage() }}
    from {{ ref('int_bq_order_items__versions') }}
    where disposition = 'ACCEPTED'
),

api_items as (
    select
        o.source_system,
        i.value:order_item_id::string as order_item_id,
        o.order_id,
        i.value:product_id::string as source_product_id,
        try_to_number(i.value:quantity::string) as quantity,
        try_to_decimal(i.value:unit_price::string, 18, 4) as unit_price,
        try_to_decimal(i.value:discount_amount::string, 18, 4) as discount_amount,
        try_to_decimal(i.value:tax_amount::string, 18, 4) as tax_amount,
        try_to_decimal(i.value:line_total::string, 18, 4) as line_total,
        o.order_at as line_created_at,
        o.source_updated_at as line_updated_at,
        o.source_record_id,
        o.batch_id as source_batch_id,
        o.version_effective_at,
        o.version_count,
        o.has_version_tie
    from {{ ref('int_api_orders__versions') }} as o,
    lateral flatten(input => o.items) as i
    where o.disposition = 'ACCEPTED'
),

api as (
    select
        'MOCK_API:' || a.order_item_id as order_item_key,
        a.source_system,
        a.order_item_id,
        'MOCK_API:' || a.order_id as order_key,
        a.order_id,
        x.target_id as product_id,
        a.source_product_id,
        a.quantity,
        a.unit_price,
        a.discount_amount,
        a.tax_amount,
        a.line_total,
        a.line_created_at,
        a.line_updated_at,
        a.source_record_id,
        a.source_batch_id,
        a.version_effective_at,
        a.version_count,
        a.has_version_tie
    from api_items as a
    left join {{ ref('api_crosswalk') }} as x
      on x.source_system = a.source_system
     and x.entity = 'product'
     and x.source_id = a.source_product_id
)

select * from bigquery
union all
select * from api
