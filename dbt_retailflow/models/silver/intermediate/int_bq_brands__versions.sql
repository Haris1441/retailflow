{{ resolve_versions(
    ref('stg_bq_brands'),
    entity='brands',
    source_system='BIGQUERY',
    content_columns=[
        'brand_id',
        'brand_name',
        'origin_country',
        'brand_status',
        'brand_created_at',
        'brand_updated_at'
    ]
) }}
