{{ resolve_versions(
    ref('stg_bq_order_items'),
    entity='order_items',
    source_system='BIGQUERY',
    content_columns=[
        'order_item_id',
        'order_id',
        'product_id',
        'quantity',
        'unit_price',
        'discount_amount',
        'tax_amount',
        'line_total',
        'line_created_at',
        'line_updated_at'
    ]
) }}
