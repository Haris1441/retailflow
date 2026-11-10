{{ resolve_versions(
    ref('stg_api_orders'),
    entity='orders',
    source_system='MOCK_API',
    content_columns=[
        'order_id',
        'customer_id',
        'api_store_id',
        'order_at',
        'fulfilled_at',
        'order_status',
        'order_channel',
        'currency',
        'order_total',
        'discount_amount',
        'shipping_amount',
        'tax_amount',
        'customer',
        'items',
        'shipping',
        'payment_references'
    ]
) }}
