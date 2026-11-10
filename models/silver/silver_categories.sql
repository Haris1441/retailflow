-- One current row per category. Parent links are kept as delivered; the BATCH_005 cycle
-- (1 -> 7 -> 4 -> 1) is detected and rejected in Phase 9 before any path flattening.
select
    category_id,
    category_name,
    parent_category_id,
    category_level,
    is_active,
    category_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_categories__versions') }}
where disposition = 'ACCEPTED'
