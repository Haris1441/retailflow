-- Phase 13: the end-to-end reconciliation must pass at every layer. Expect zero rows.
-- On failure, open the detail_model named in the row and filter on status = 'FAIL'.
select *
from {{ ref('recon_summary') }}
where status <> 'PASS'
