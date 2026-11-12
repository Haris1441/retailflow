select
    supplier_id,
    supplier_name,
    contact_email,
    country,
    lead_time_days,
    supplier_status,
    {{ silver_lineage() }}
from {{ ref('int_bq_suppliers__versions') }}
where disposition = 'ACCEPTED'
