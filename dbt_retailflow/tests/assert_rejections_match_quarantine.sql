-- Every REJECTED delivery must be OPEN in quarantine, and every OPEN quarantine row must be
-- REJECTED (or a DUPLICATE copy of a rejected delivery). Expect zero rows.
select
    coalesce(d.delivery_key, q.delivery_key) as delivery_key,
    d.disposition,
    q.quarantine_status
from (
    select delivery_key, disposition
    from {{ ref('silver_record_dispositions') }}
    where disposition = 'REJECTED'
) as d
full outer join (
    select delivery_key, quarantine_status
    from {{ ref('dq_quarantine') }}
    where quarantine_status = 'OPEN'
      and delivery_disposition <> 'DUPLICATE'
) as q
  on q.delivery_key = d.delivery_key
where d.delivery_key is null
   or q.delivery_key is null
