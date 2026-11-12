{{ resolve_versions(
    ref('stg_api_events'),
    entity='events',
    source_system='MOCK_API',
    content_columns=[
        'event_id',
        'customer_id',
        'event_at',
        'event_type',
        'event_payload',
        'event_updated_at'
    ]
) }}
