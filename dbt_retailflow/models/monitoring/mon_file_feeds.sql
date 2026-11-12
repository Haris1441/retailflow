-- Phase 14 · One row per configured feed: is it arriving, is it healthy?
-- Times are processing times (when our pipeline handled the file), not the fixture's business
-- dates, so "hours since last load" is real operational freshness.
--   freshness_status  NO_FILES_YET | ON_TIME | LATE (no load within EXPECTED_EVERY_HOURS)
--   health            OK | ATTENTION (a file whose latest attempt failed, or an attempt stuck in RECEIVED)
with config as (
    select feed_name, source_system, entity, file_pattern, expected_every_hours, is_enabled
    from {{ source('control', 'file_config') }}
),

attempts as (
    select *,
        row_number() over (partition by file_name order by detected_at desc, attempt_id desc) = 1 as is_latest_attempt
    from {{ source('control', 'file_registry') }}
),

per_feed as (
    select
        feed_name,
        count_if(status = 'LOADED') as files_loaded,
        count_if(status = 'SKIPPED') as files_skipped,
        count_if(status = 'FAILED') as failed_attempts,
        count_if(is_latest_attempt and status = 'FAILED') as open_failures,
        count_if(status = 'RECEIVED' and detected_at < dateadd(hour, -1, current_timestamp())) as stuck_attempts,
        coalesce(sum(iff(status = 'LOADED', inserted_rows, 0)), 0) as rows_inserted,
        max(iff(status = 'LOADED', finished_at, null)) as last_loaded_at,
        max_by(iff(status = 'LOADED', batch_id, null), iff(status = 'LOADED', finished_at, null)) as last_loaded_batch
    from attempts
    where feed_name is not null
    group by feed_name
)

select
    c.feed_name,
    c.source_system,
    c.entity,
    c.file_pattern,
    c.is_enabled,
    c.expected_every_hours,
    coalesce(p.files_loaded, 0) as files_loaded,
    coalesce(p.files_skipped, 0) as files_skipped,
    coalesce(p.failed_attempts, 0) as failed_attempts,
    coalesce(p.open_failures, 0) as open_failures,
    coalesce(p.stuck_attempts, 0) as stuck_attempts,
    coalesce(p.rows_inserted, 0) as rows_inserted,
    p.last_loaded_at,
    p.last_loaded_batch,
    datediff(minute, p.last_loaded_at, current_timestamp()) / 60.0 as hours_since_last_load,
    case
        when p.last_loaded_at is null then 'NO_FILES_YET'
        when datediff(minute, p.last_loaded_at, current_timestamp()) > c.expected_every_hours * 60 then 'LATE'
        else 'ON_TIME'
    end as freshness_status,
    iff(coalesce(p.open_failures, 0) + coalesce(p.stuck_attempts, 0) > 0, 'ATTENTION', 'OK') as health
from config as c
left join per_feed as p
  on p.feed_name = c.feed_name
