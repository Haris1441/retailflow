{#
  dq_with_waivers: finish a checks model.
  Expects a CTE named `failures` with one row per failed rule and delivery:
    source_system, entity, source_record_id, business_key, batch_id, rule_id, severity, observed_value
  Adds delivery_key, failure_key and the waiver decision from the dq_waivers seed.
#}
{% macro dq_with_waivers() %}
select
    f.source_system || ':' || f.entity || ':' || f.source_record_id as delivery_key,
    f.source_system || ':' || f.entity || ':' || f.source_record_id || ':' || f.rule_id as failure_key,
    f.source_system,
    f.entity,
    f.source_record_id,
    f.business_key,
    f.batch_id,
    f.rule_id,
    f.severity,
    f.observed_value::varchar as observed_value,
    w.delivery_key is not null as is_waived,
    w.reason as waiver_reason,
    w.approved_by as waiver_approved_by,
    w.approved_on as waiver_approved_on
from failures as f
left join {{ ref('dq_waivers') }} as w
  on w.delivery_key = f.source_system || ':' || f.entity || ':' || f.source_record_id
 and w.rule_id = f.rule_id
 and w.decision = 'ACCEPT'
{% endmacro %}
