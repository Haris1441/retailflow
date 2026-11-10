-- One row per delivery that failed at least one REJECT rule, with its raw payload for review.
-- quarantine_status:
--   OPEN    rejected; not current in Silver. Fix at the source (new delivery) or add a waiver.
--   WAIVED  every REJECT failure on it has an approved waiver, so it was allowed through.
with reject_failures as (
    select
        delivery_key,
        source_system,
        entity,
        source_record_id,
        business_key,
        batch_id,
        listagg(rule_id, ', ') within group (order by rule_id) as failed_rules,
        listagg(observed_value, ' | ') within group (order by rule_id) as observed_values,
        count_if(not is_waived) as open_failures,
        max(waiver_approved_by) as waiver_approved_by
    from {{ ref('dq_rule_results') }}
    where severity = 'REJECT'
    group by 1, 2, 3, 4, 5, 6
)

select
    q.*,
    iff(q.open_failures > 0, 'OPEN', 'WAIVED') as quarantine_status,
    d.disposition as delivery_disposition,
    b.source_available_at,
    b.raw_payload
from reject_failures as q
left join {{ ref('silver_record_dispositions') }} as d
  on d.delivery_key = q.delivery_key
left join {{ source('bronze', 'source_records') }} as b
  on b.source_system = q.source_system
 and b.entity = q.entity
 and b.source_record_id = q.source_record_id
