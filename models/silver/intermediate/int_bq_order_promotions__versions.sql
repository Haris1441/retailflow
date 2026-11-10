{{ resolve_versions(
    ref('stg_bq_order_promotions'),
    entity='order_promotions',
    source_system='BIGQUERY',
    content_columns=[
        'order_promotion_id',
        'order_id',
        'promotion_id',
        'applied_discount_amount',
        'applied_at',
        'order_promotion_updated_at'
    ]
) }}
