-- Every Bronze delivery gets exactly one Silver disposition.
-- Returns a row for any source_system/entity whose counts differ. Expect zero rows.
with bronze as (
    select source_system, entity, count(*) as bronze_rows
    from {{ source('bronze', 'source_records') }}
    where {{ cdc_visible() }}
    group by 1, 2
),
silver as (
    select source_system, entity, count(*) as disposition_rows
    from {{ ref('silver_record_dispositions') }}
    group by 1, 2
)
select
    coalesce(b.source_system, s.source_system) as source_system,
    coalesce(b.entity, s.entity) as entity,
    b.bronze_rows,
    s.disposition_rows
from bronze as b
full outer join silver as s
  on b.source_system = s.source_system and b.entity = s.entity
where b.bronze_rows is distinct from s.disposition_rows
