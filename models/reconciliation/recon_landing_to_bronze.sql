-- Layer 0 · Landed file -> Bronze load (Phase 14). Every LOADED file must point to the audited
-- Bronze run that loaded it, and the counts must agree end to end:
--   control file row_count = rows read from the file = rows the load run extracted
--   rows inserted + rows already present = what the file registry recorded
-- Before the first file arrives this model is empty and the check passes with 0 items.
with files as (
    select attempt_id, file_name, feed_name, source_system, entity, batch_id, expected_rows,
           extracted_rows, inserted_rows, matched_rows, run_id, finished_at
    from {{ source('control', 'file_registry') }}
    where status = 'LOADED'
),

audit_runs as (
    select run_id, source_system, batch_id, entity_scope, extracted_count, inserted_count, matched_count
    from {{ source('audit', 'bronze_load_runs') }}
)

select
    f.attempt_id,
    f.file_name,
    f.feed_name,
    f.batch_id,
    f.run_id,
    f.expected_rows,
    f.extracted_rows,
    a.extracted_count as audit_extracted_count,
    f.inserted_rows,
    a.inserted_count as audit_inserted_count,
    f.matched_rows,
    a.matched_count as audit_matched_count,
    case
        when a.run_id is null then 'FAIL'
        when a.source_system <> f.source_system or a.batch_id <> f.batch_id or a.entity_scope <> f.entity then 'FAIL'
        when f.expected_rows is not null and f.expected_rows <> f.extracted_rows then 'FAIL'
        when a.extracted_count <> f.extracted_rows then 'FAIL'
        when a.inserted_count <> f.inserted_rows or a.matched_count <> f.matched_rows then 'FAIL'
        else 'PASS'
    end as status,
    case
        when a.run_id is null then 'Loaded file has no audited Bronze run'
        when a.source_system <> f.source_system or a.batch_id <> f.batch_id or a.entity_scope <> f.entity
            then 'Audited run belongs to a different source, batch or entity'
        when f.expected_rows is not null and f.expected_rows <> f.extracted_rows then 'Control file count differs from rows read'
        when a.extracted_count <> f.extracted_rows then 'Audit extracted count differs from rows read'
        when a.inserted_count <> f.inserted_rows or a.matched_count <> f.matched_rows
            then 'Inserted or matched counts differ between registry and audit'
    end as failure_reason
from files as f
left join audit_runs as a
  on a.run_id = f.run_id
