{{ resolve_versions(
    ref('stg_bq_customers'),
    entity='customers',
    source_system='BIGQUERY',
    content_columns=[
        'customer_id',
        'first_name',
        'last_name',
        'email_normalized',
        'phone',
        'gender',
        'preferred_language',
        'addresses',
        'birth_date',
        'registration_date',
        'customer_status',
        'loyalty_tier',
        'country',
        'city',
        'address',
        'postal_code',
        'customer_created_at',
        'customer_updated_at',
        'is_deleted'
    ]
) }}
