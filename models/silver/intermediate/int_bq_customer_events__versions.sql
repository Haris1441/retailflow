{{ resolve_versions(
    ref('stg_bq_customer_events'),
    entity='customer_events',
    source_system='BIGQUERY',
    content_columns=[
        'event_id',
        'customer_id',
        'event_at',
        'event_type',
        'event_payload'
    ]
) }}
