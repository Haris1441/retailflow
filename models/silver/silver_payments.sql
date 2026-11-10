{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='payment_key',
        on_schema_change='fail',
        post_hook="delete from {{ this }} where key_disposition <> 'ACCEPTED'"
    )
}}
-- depends_on: {{ ref('stg_bq_payments') }}
-- depends_on: {{ ref('stg_api_payments') }}
-- One current payment attempt or refund event per source system.
-- The API payments endpoint is authoritative for API payment events; the payment references
-- nested in API orders are not a second source of cash.
--
-- Phase 10: incremental. An incremental run rebuilds only keys with a Bronze delivery after
-- the watermark (macros/cdc.sql), from every delivery of those keys. delete+insert replaces
-- their rows; the post-hook removes keys whose top version is no longer ACCEPTED.
with bigquery_versions as (
    select
        v.*,
        max(v.source_available_at) over (partition by v.business_key) as last_delivery_available_at
    from {{ ref('int_bq_payments__versions') }} as v
    {% if is_incremental() %}
    where v.business_key in ({{ incremental_affected_keys(ref('stg_bq_payments'), 'BIGQUERY') }})
    {% endif %}
),

api_versions as (
    select
        v.*,
        max(v.source_available_at) over (partition by v.business_key) as last_delivery_available_at
    from {{ ref('int_api_payments__versions') }} as v
    {% if is_incremental() %}
    where v.business_key in ({{ incremental_affected_keys(ref('stg_api_payments'), 'MOCK_API') }})
    {% endif %}
),

bigquery as (
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
        {{ silver_lineage() }},
        {{ silver_incremental_columns() }}
    from bigquery_versions
    where version_rank = 1
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
        {{ silver_lineage() }},
        {{ silver_incremental_columns() }}
    from api_versions
    where version_rank = 1
)

select * from bigquery
union all
select * from api
