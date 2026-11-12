{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='event_key',
        on_schema_change='fail',
        post_hook="delete from {{ this }} where key_disposition <> 'ACCEPTED'"
    )
}}
-- depends_on: {{ ref('stg_bq_customer_events') }}
-- depends_on: {{ ref('stg_api_events') }}
-- One current row per event per source system. The 240 re-sent BATCH_005 events are DUPLICATE
-- dispositions, and event 401's DELETE tombstone removes it, so BigQuery has 11,999 events.
--
-- Phase 10: incremental, same pattern as silver_payments. When event 401's tombstone arrives,
-- its key is rewritten with key_disposition DELETED and the post-hook removes the row.
with bigquery_versions as (
    select
        v.*,
        max(v.source_available_at) over (partition by v.business_key) as last_delivery_available_at
    from {{ ref('int_bq_customer_events__versions') }} as v
    {% if is_incremental() %}
    where v.business_key in ({{ incremental_affected_keys(ref('stg_bq_customer_events'), 'BIGQUERY') }})
    {% endif %}
),

api_versions as (
    select
        v.*,
        max(v.source_available_at) over (partition by v.business_key) as last_delivery_available_at
    from {{ ref('int_api_events__versions') }} as v
    {% if is_incremental() %}
    where v.business_key in ({{ incremental_affected_keys(ref('stg_api_events'), 'MOCK_API') }})
    {% endif %}
),

bigquery as (
    select
        'BIGQUERY:' || event_id::varchar as event_key,
        source_system,
        event_id::varchar as event_id,
        customer_id::varchar as customer_id,
        iff(customer_id is null, null, 'BIGQUERY:' || customer_id::varchar) as customer_key,
        event_at,
        event_type,
        session_id,
        device_type,
        lower(trim(event_payload:device:os::string)) as device_os,
        campaign_channel,
        event_payload,
        {{ silver_lineage() }},
        {{ silver_incremental_columns() }}
    from bigquery_versions
    where version_rank = 1
),

api as (
    select
        'MOCK_API:' || event_id as event_key,
        source_system,
        event_id,
        customer_id,
        iff(customer_id is null, null, 'MOCK_API:' || customer_id) as customer_key,
        event_at,
        event_type,
        session_id,
        device_type,
        lower(trim(event_payload:device:os::string)) as device_os,
        campaign_channel,
        event_payload,
        {{ silver_lineage() }},
        {{ silver_incremental_columns() }}
    from api_versions
    where version_rank = 1
)

select * from bigquery
union all
select * from api
