{{ resolve_versions(
    ref('stg_bq_promotions'),
    entity='promotions',
    source_system='BIGQUERY',
    content_columns=[
        'promotion_id',
        'promotion_name',
        'promotion_type',
        'discount_value',
        'start_date',
        'end_date',
        'promotion_status',
        'promotion_updated_at'
    ]
) }}
