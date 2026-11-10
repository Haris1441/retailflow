{{ resolve_versions(
    ref('stg_bq_stores'),
    entity='stores',
    source_system='BIGQUERY',
    content_columns=[
        'store_id',
        'store_name',
        'store_type',
        'country',
        'region',
        'city',
        'currency',
        'channel',
        'opening_date',
        'store_status',
        'store_updated_at'
    ]
) }}
