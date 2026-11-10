-- One current row per event per source system. The 240 re-sent BATCH_005 events are DUPLICATE
-- dispositions, and event 401's DELETE tombstone removes it, so BigQuery has 11,999 events.
with bigquery as (
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
        {{ silver_lineage() }}
    from {{ ref('int_bq_customer_events__versions') }}
    where disposition = 'ACCEPTED'
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
        {{ silver_lineage() }}
    from {{ ref('int_api_events__versions') }}
    where disposition = 'ACCEPTED'
)

select * from bigquery
union all
select * from api
