-- Layer 1b · Bronze <-> load audit. The loader writes one AUDIT.BRONZE_LOAD_RUNS row in the same
-- transaction as each load, so for every run the Bronze rows stamped with its run_id must equal
-- its inserted_count, and every Bronze row must belong to an audited run.
-- Replays (inserted_count 0, matched_count = distinct_count) prove retries added nothing.
with audit_runs as (
    select run_id, source_system, batch_id, entity_scope, extracted_count, distinct_count,
           inserted_count, matched_count, finished_at
    from {{ source('audit', 'bronze_load_runs') }}
),

bronze_runs as (
    select run_id, min(source_system) as source_system, min(batch_id) as batch_id, count(*) as bronze_rows
    from {{ source('bronze', 'source_records') }}
    group by run_id
)

select
    coalesce(a.run_id, b.run_id) as run_id,
    coalesce(a.source_system, b.source_system) as source_system,
    coalesce(a.batch_id, b.batch_id) as batch_id,
    a.entity_scope,
    a.finished_at,
    a.extracted_count,
    a.distinct_count,
    coalesce(a.inserted_count, 0) as inserted_count,
    coalesce(a.matched_count, 0) as matched_count,
    coalesce(b.bronze_rows, 0) as bronze_rows,
    a.inserted_count = 0 and a.matched_count = a.distinct_count as is_replay,
    case
        when a.run_id is null then 'FAIL'
        when coalesce(b.bronze_rows, 0) <> a.inserted_count then 'FAIL'
        when a.inserted_count + a.matched_count <> a.distinct_count then 'FAIL'
        else 'PASS'
    end as status,
    case
        when a.run_id is null then 'Bronze rows without an audited load run'
        when coalesce(b.bronze_rows, 0) <> a.inserted_count then 'Bronze rows differ from inserted_count'
        when a.inserted_count + a.matched_count <> a.distinct_count then 'inserted + matched differs from distinct'
    end as failure_reason
from audit_runs as a
full outer join bronze_runs as b
  on b.run_id = a.run_id
