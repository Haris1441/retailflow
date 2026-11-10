{#
  resolve_versions: classify every Bronze delivery of one entity and pick the current version.

  One output row per staging row (one per Bronze physical delivery), with:
    version_effective_at  business time used to order versions
    content_hash          hash of the business columns (metadata excluded)
    content_delivery_rank 1 for the first delivery of a given content, >1 for later identical copies
    is_rejected           the delivery failed a REJECT rule that is not waived (Phase 9)
    version_rank          1 = current version of the business key
    version_count         distinct versions (copies excluded) seen for the key
    has_version_tie       two different trusted contents share the same effective and availability time
    disposition           ACCEPTED | SUPERSEDED | DUPLICATE | REJECTED | DELETED

  Ordering rules
    - Business time first: source_effective_at (change batches), else the entity's own
      payload time (effective_expr, usually source_updated_at), else source_available_at.
      Baseline rows have no source_effective_at, so the payload time keeps a backdated
      correction (BATCH_006) ordered by when it happened, not when it arrived.
    - Ties on business time go to the later availability, then the higher record ID.
    - A delivery whose content (and operation) matches an earlier delivery of the same key
      is a DUPLICATE (for example the 240 re-sent events in BATCH_005). It never wins.
    - Rejected deliveries rank after every trusted version, so the latest TRUSTED version
      wins. If a key has no trusted version, its top row is REJECTED and the key has no
      current row (it is quarantined).
    - If the winning version is a DELETE tombstone, the key is DELETED and has no current row.

  checks: optional relation of rule failures for this entity (source_record_id, severity,
  is_waived). Only unwaived REJECT failures reject a delivery.

  Known limit: content that reverts to an earlier value (A -> B -> A) would classify the
  second A as a duplicate. The fixtures contain no reverts. Phase 10 revisits ordering.
#}
{% macro resolve_versions(relation, entity, content_columns, effective_expr='source_updated_at', source_system=none, checks=none) %}
with base as (
    select
        s.*,
        coalesce(s.source_effective_at, {{ effective_expr }}, s.source_available_at) as version_effective_at,
        hash({{ content_columns | join(', ') }}) as content_hash,
        {% if checks %}coalesce(r.is_rejected, false){% else %}false{% endif %} as is_rejected
    from {{ relation }} as s
    {% if checks %}
    left join (
        select source_record_id, true as is_rejected
        from {{ checks }}
        where severity = 'REJECT' and not is_waived
        group by source_record_id
    ) as r
      on r.source_record_id = s.source_record_id
    {% endif %}
),
copies as (
    select
        base.*,
        row_number() over (
            partition by business_key, content_hash, source_operation
            order by source_available_at, batch_id, source_record_id
        ) as content_delivery_rank
    from base
),
ranked as (
    select
        copies.*,
        row_number() over (
            partition by business_key
            order by iff(content_delivery_rank = 1, 0, 1),
                     iff(is_rejected, 1, 0),
                     version_effective_at desc,
                     source_available_at desc,
                     source_record_id desc
        ) as version_rank,
        sum(iff(content_delivery_rank = 1, 1, 0)) over (partition by business_key) as version_count,
        sum(iff(content_delivery_rank = 1 and not is_rejected, 1, 0)) over (
            partition by business_key, version_effective_at, source_available_at
        ) as versions_at_same_time
    from copies
)
select
    {% if source_system %}'{{ source_system }}' as source_system,{% endif %}
    '{{ entity }}' as entity,
    ranked.*,
    versions_at_same_time > 1 as has_version_tie,
    case
        when content_delivery_rank > 1 then 'DUPLICATE'
        when is_rejected then 'REJECTED'
        when version_rank > 1 then 'SUPERSEDED'
        when source_operation = 'DELETE' then 'DELETED'
        else 'ACCEPTED'
    end as disposition
from ranked
{% endmacro %}
