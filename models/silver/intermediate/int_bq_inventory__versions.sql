{{ resolve_versions(
    ref('stg_bq_inventory'),
    entity='inventory',
    source_system='BIGQUERY',
    content_columns=[
        'inventory_id',
        'store_id',
        'product_id',
        'snapshot_date',
        'quantity_on_hand',
        'reserved_quantity',
        'reorder_level',
        'inventory_updated_at'
    ]
) }}
