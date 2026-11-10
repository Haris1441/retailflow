{{ resolve_versions(
    ref('stg_bq_payments'),
    entity='payments',
    source_system='BIGQUERY',
    content_columns=[
        'payment_id',
        'order_id',
        'payment_method',
        'payment_status',
        'payment_type',
        'payment_amount',
        'payment_currency',
        'payment_at',
        'transaction_reference',
        'payment_updated_at',
        'return_id'
    ]
) }}
