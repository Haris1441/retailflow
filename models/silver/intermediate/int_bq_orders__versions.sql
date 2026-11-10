{{ resolve_versions(
    ref('stg_bq_orders'),
    entity='orders',
    source_system='BIGQUERY',
    content_columns=[
        'order_id',
        'customer_id',
        'store_id',
        'order_at',
        'order_status',
        'order_channel',
        'currency',
        'order_total',
        'discount_amount',
        'shipping_amount',
        'tax_amount',
        'order_created_at',
        'order_updated_at',
        'fulfilled_at',
        'is_deleted'
    ]
) }}
