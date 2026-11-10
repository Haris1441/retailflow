{{ resolve_versions(
    ref('stg_bq_exchange_rates'),
    entity='exchange_rates',
    source_system='BIGQUERY',
    content_columns=[
        'rate_date',
        'from_currency',
        'to_currency',
        'exchange_rate',
        'rate_effective_at'
    ],
    effective_expr='rate_effective_at'
) }}
