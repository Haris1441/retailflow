{{ resolve_versions(
    ref('stg_bq_returns'),
    entity='returns',
    source_system='BIGQUERY',
    content_columns=[
        'return_id',
        'order_id',
        'order_item_id',
        'product_id',
        'return_quantity',
        'return_reason',
        'return_status',
        'refund_amount',
        'requested_at',
        'completed_at',
        'return_updated_at'
    ]
) }}
