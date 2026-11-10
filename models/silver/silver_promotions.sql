select
    promotion_id,
    promotion_name,
    promotion_type,
    discount_value,
    start_date,
    end_date,
    promotion_status,
    promotion_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_promotions__versions') }}
where disposition = 'ACCEPTED'
