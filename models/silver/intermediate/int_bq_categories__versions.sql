{{ resolve_versions(
    ref('stg_bq_categories'),
    entity='categories',
    source_system='BIGQUERY',
    content_columns=[
        'category_id',
        'category_name',
        'parent_category_id',
        'category_level',
        'is_active',
        'category_updated_at'
    ]
) }}
