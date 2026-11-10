{{ resolve_versions(
    ref('stg_bq_suppliers'),
    entity='suppliers',
    source_system='BIGQUERY',
    content_columns=[
        'supplier_id',
        'supplier_name',
        'contact_email',
        'country',
        'lead_time_days',
        'supplier_status'
    ]
) }}
