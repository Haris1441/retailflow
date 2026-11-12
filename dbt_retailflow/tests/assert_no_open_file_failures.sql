-- Phase 14 alert: a landed file failed or is stuck and nobody has resent or rerun it yet.
-- Severity warn: the build still publishes the data that did load, but the run shows a warning
-- until the file is resent or reprocessed. Rejected file names are listed in
-- mon_open_file_issues without raising this alert.
{{ config(severity='warn', tags=['monitoring']) }}

select *
from {{ ref('mon_open_file_issues') }}
where issue_type in ('FAILED', 'STUCK')
