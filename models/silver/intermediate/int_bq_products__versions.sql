{{ resolve_versions(
    ref('stg_bq_products'),
    entity='products',
    source_system='BIGQUERY',
    checks=ref('dq_bq_products__checks'),
    content_columns=[
        'product_id',
        'sku',
        'product_name',
        'description',
        'category_id',
        'brand_id',
        'supplier_id',
        'base_price',
        'cost_price',
        'currency',
        'product_status',
        'product_created_at',
        'product_updated_at'
    ]
) }}
