-- One snapshot per store, product and date per source system.
-- API store and product IDs map to BigQuery keys through the api_crosswalk seed.
with bigquery as (
    select
        'BIGQUERY:' || inventory_id as inventory_key,
        source_system,
        inventory_id,
        store_id,
        product_id,
        store_id::varchar as source_store_id,
        product_id::varchar as source_product_id,
        snapshot_date,
        quantity_on_hand,
        reserved_quantity,
        reorder_level,
        inventory_updated_at,
        {{ silver_lineage() }}
    from {{ ref('int_bq_inventory__versions') }}
    where disposition = 'ACCEPTED'
),

api as (
    select
        'MOCK_API:' || i.inventory_id as inventory_key,
        i.source_system,
        i.inventory_id,
        s.target_id as store_id,
        p.target_id as product_id,
        i.store_id as source_store_id,
        i.product_id as source_product_id,
        i.snapshot_date,
        i.quantity_on_hand,
        i.reserved_quantity,
        i.reorder_level,
        i.inventory_updated_at,
        i.source_record_id,
        i.batch_id as source_batch_id,
        i.version_effective_at,
        i.version_count,
        i.has_version_tie
    from {{ ref('int_api_inventory__versions') }} as i
    left join {{ ref('api_crosswalk') }} as s
      on s.source_system = i.source_system and s.entity = 'store' and s.source_id = i.store_id
    left join {{ ref('api_crosswalk') }} as p
      on p.source_system = i.source_system and p.entity = 'product' and p.source_id = i.product_id
    where i.disposition = 'ACCEPTED'
)

select * from bigquery
union all
select * from api
