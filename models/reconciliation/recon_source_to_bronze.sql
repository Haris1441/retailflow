-- Layer 1 · Source -> Bronze. Physical rows per source system, entity and batch must equal the
-- source manifest. A missing batch, an extra batch or a partial load shows as a FAIL row.
with manifest as (
    select source_system, entity, batch_id, expected_rows
    from {{ ref('source_manifest') }}
    where {{ cdc_visible() }}
),

bronze as (
    select source_system, entity, batch_id, count(*) as bronze_rows
    from {{ source('bronze', 'source_records') }}
    where {{ cdc_visible() }}
    group by 1, 2, 3
)

select
    coalesce(m.source_system, b.source_system) as source_system,
    coalesce(m.entity, b.entity) as entity,
    coalesce(m.batch_id, b.batch_id) as batch_id,
    coalesce(m.expected_rows, 0) as source_rows,
    coalesce(b.bronze_rows, 0) as bronze_rows,
    coalesce(b.bronze_rows, 0) - coalesce(m.expected_rows, 0) as difference,
    iff(coalesce(b.bronze_rows, 0) = coalesce(m.expected_rows, 0), 'PASS', 'FAIL') as status
from manifest as m
full outer join bronze as b
  on b.source_system = m.source_system
 and b.entity = m.entity
 and b.batch_id = m.batch_id
