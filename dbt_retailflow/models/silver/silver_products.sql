-- One current row per product. BigQuery owns the catalog.
-- Phase 8 takes the latest version; the BATCH_005 negative-price and missing-category changes
-- (products 31-45) are current here and become rejections with fallback in Phase 9.
select
    product_id,
    sku,
    product_name,
    description,
    category_id,
    brand_id,
    supplier_id,
    base_price,
    cost_price,
    currency,
    product_status,
    product_created_at,
    product_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_products__versions') }}
where disposition = 'ACCEPTED'
