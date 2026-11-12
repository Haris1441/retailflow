select
    brand_id,
    brand_name,
    origin_country,
    brand_status,
    brand_created_at,
    brand_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_brands__versions') }}
where disposition = 'ACCEPTED'
