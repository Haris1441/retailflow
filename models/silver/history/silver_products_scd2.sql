-- SCD Type 2 product history (Phase 11). Price and classification changes start a new row,
-- so Gold can value a sale at the price and category in force on the order date.
--
-- Type 2: category, brand, supplier, base price, cost price, status
-- Type 1: SKU, name, description, currency
--
-- The 15 rejected BATCH_005 changes (products 31-45) are excluded, so a quarantined price never
-- appears in history, not even for a closed period.
with versions as (
    select
        product_id,
        category_id,
        brand_id,
        supplier_id,
        base_price,
        cost_price,
        product_status,
        sku,
        product_name,
        description,
        currency,
        version_effective_at,
        source_available_at,
        source_record_id,
        batch_id,
        source_operation
    from {{ ref('int_bq_products__versions') }}
    where disposition not in ('DUPLICATE', 'REJECTED')
),

{{ scd2_history(
    'versions',
    key_column='product_id',
    tracked_columns=[
        'category_id',
        'brand_id',
        'supplier_id',
        'base_price',
        'cost_price',
        'product_status'
    ],
    type1_columns=[
        'sku',
        'product_name',
        'description',
        'currency'
    ]
) }}
