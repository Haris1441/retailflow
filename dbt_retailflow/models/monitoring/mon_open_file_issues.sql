-- Phase 14 · The operator's work list: files that need someone. Empty means nothing to do.
--   FAILED         the latest attempt for this file name failed; nothing was loaded. Fix: ask the
--                  client to resend (python -m landing simulate --scenario resend plays that part).
--   STUCK          an attempt has been RECEIVED for over an hour: the process stopped mid-file.
--                  Fix: run a scan; it moves the file back from processing/ and reloads it safely.
--   REJECTED_NAME  the file name matches no feed. Fix: agree the name with the client, or add a
--                  FILE_CONFIG row if it is a new feed. Resolved once a file of the same name loads.
with attempts as (
    select *,
        row_number() over (partition by file_name order by detected_at desc, attempt_id desc) as attempt_rank
    from {{ source('control', 'file_registry') }}
)

select
    attempt_id,
    file_name,
    feed_name,
    batch_id,
    case
        when status = 'FAILED' then 'FAILED'
        when status = 'RECEIVED' then 'STUCK'
        else 'REJECTED_NAME'
    end as issue_type,
    error_message,
    detected_at,
    finished_at
from attempts
where attempt_rank = 1
  and (status in ('FAILED', 'REJECTED')
       or (status = 'RECEIVED' and detected_at < dateadd(hour, -1, current_timestamp())))
