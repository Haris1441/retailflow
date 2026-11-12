{{ resolve_versions(
    ref('stg_api_customers'),
    entity='customers',
    source_system='MOCK_API',
    content_columns=[
        'customer_id',
        'email_normalized',
        'customer_created_at',
        'customer_updated_at'
    ]
) }}
