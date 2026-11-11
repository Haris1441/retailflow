-- Layer 2 · Bronze -> Silver. Every visible Bronze delivery has exactly one terminal disposition,
-- reconciled per source system, entity and batch, with the disposition breakdown.
with bronze as (
    select source_system, entity, batch_id, count(*) as bronze_rows
    from {{ source('bronze', 'source_records') }}
    where {{ cdc_visible() }}
    group by 1, 2, 3
),

dispositions as (
    select
        source_system,
        entity,
        batch_id,
        count(*) as disposition_rows,
        count_if(disposition = 'ACCEPTED') as accepted,
        count_if(disposition = 'SUPERSEDED') as superseded,
        count_if(disposition = 'DUPLICATE') as duplicate,
        count_if(disposition = 'REJECTED') as rejected,
        count_if(disposition = 'DELETED') as deleted
    from {{ ref('silver_record_dispositions') }}
    group by 1, 2, 3
)

select
    coalesce(b.source_system, d.source_system) as source_system,
    coalesce(b.entity, d.entity) as entity,
    coalesce(b.batch_id, d.batch_id) as batch_id,
    coalesce(b.bronze_rows, 0) as bronze_rows,
    coalesce(d.disposition_rows, 0) as disposition_rows,
    coalesce(d.accepted, 0) as accepted,
    coalesce(d.superseded, 0) as superseded,
    coalesce(d.duplicate, 0) as duplicate,
    coalesce(d.rejected, 0) as rejected,
    coalesce(d.deleted, 0) as deleted,
    coalesce(d.disposition_rows, 0) - coalesce(b.bronze_rows, 0) as difference,
    iff(coalesce(d.disposition_rows, 0) = coalesce(b.bronze_rows, 0), 'PASS', 'FAIL') as status
from bronze as b
full outer join dispositions as d
  on d.source_system = b.source_system
 and d.entity = b.entity
 and d.batch_id = b.batch_id
