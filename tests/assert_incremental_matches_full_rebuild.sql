-- Phase 10: an incremental Silver table must hold exactly what a full rebuild would produce.
-- Recompute the current winner of every key from all visible deliveries and compare it with
-- the incremental table by key and winning Bronze delivery. Every other column is derived
-- from that delivery. Expect zero rows.
with expected as (
    select 'silver_payments' as silver_table, 'BIGQUERY:' || payment_id::varchar as silver_key, source_record_id
    from {{ ref('int_bq_payments__versions') }}
    where version_rank = 1 and disposition = 'ACCEPTED'
    union all
    select 'silver_payments', 'MOCK_API:' || payment_id, source_record_id
    from {{ ref('int_api_payments__versions') }}
    where version_rank = 1 and disposition = 'ACCEPTED'
    union all
    select 'silver_customer_events', 'BIGQUERY:' || event_id::varchar, source_record_id
    from {{ ref('int_bq_customer_events__versions') }}
    where version_rank = 1 and disposition = 'ACCEPTED'
    union all
    select 'silver_customer_events', 'MOCK_API:' || event_id, source_record_id
    from {{ ref('int_api_events__versions') }}
    where version_rank = 1 and disposition = 'ACCEPTED'
),

actual as (
    select 'silver_payments' as silver_table, payment_key as silver_key, source_record_id
    from {{ ref('silver_payments') }}
    union all
    select 'silver_customer_events', event_key, source_record_id
    from {{ ref('silver_customer_events') }}
)

select
    coalesce(e.silver_table, a.silver_table) as silver_table,
    coalesce(e.silver_key, a.silver_key) as silver_key,
    e.source_record_id as expected_record_id,
    a.source_record_id as actual_record_id
from expected as e
full outer join actual as a
  on a.silver_table = e.silver_table
 and a.silver_key = e.silver_key
where e.source_record_id is distinct from a.source_record_id
