-- One current payment attempt or refund event per source system.
-- The API payments endpoint is authoritative for API payment events; the payment references
-- nested in API orders are not a second source of cash.
with bigquery as (
    select
        'BIGQUERY:' || payment_id::varchar as payment_key,
        source_system,
        payment_id::varchar as payment_id,
        'BIGQUERY:' || order_id::varchar as order_key,
        order_id::varchar as order_id,
        payment_method,
        payment_status,
        payment_type,
        payment_amount,
        payment_currency,
        payment_at,
        transaction_reference,
        return_id,
        payment_updated_at,
        {{ silver_lineage() }}
    from {{ ref('int_bq_payments__versions') }}
    where disposition = 'ACCEPTED'
),

api as (
    select
        'MOCK_API:' || payment_id as payment_key,
        source_system,
        payment_id,
        'MOCK_API:' || order_id as order_key,
        order_id,
        payment_method,
        payment_status,
        null::varchar as payment_type,
        payment_amount,
        payment_currency,
        payment_at,
        null::varchar as transaction_reference,
        null::number as return_id,
        payment_updated_at,
        {{ silver_lineage() }}
    from {{ ref('int_api_payments__versions') }}
    where disposition = 'ACCEPTED'
)

select * from bigquery
union all
select * from api
