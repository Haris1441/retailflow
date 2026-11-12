{{ resolve_versions(
    ref('stg_api_payments'),
    entity='payments',
    source_system='MOCK_API',
    content_columns=[
        'payment_id',
        'order_id',
        'payment_method',
        'payment_status',
        'payment_amount',
        'payment_currency',
        'payment_at',
        'payment_updated_at'
    ]
) }}
