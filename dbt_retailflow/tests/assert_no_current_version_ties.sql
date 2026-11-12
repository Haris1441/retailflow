{{ config(severity='warn') }}
-- A current row picked from two different versions with the same business time and
-- availability is a tie the ordering cannot resolve safely. These go to review (Phase 9).
-- Expect zero rows.
select delivery_key, source_system, entity, business_key
from {{ ref('silver_record_dispositions') }}
where disposition = 'ACCEPTED'
  and has_version_tie
