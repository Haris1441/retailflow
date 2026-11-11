-- Product dimension, SCD Type 2 on price and classification (Phase 11 history), enriched with
-- the category hierarchy and brand. The category id is historical (Type 2); category and brand
-- names are current (Type 1). 'UNKNOWN' is the governed unknown member.
select
    p.history_key as product_sk,
    p.product_id,
    p.sku,
    p.product_name,
    p.category_id,
    c3.category_name,
    c2.category_name as subcategory_name,
    c1.category_name as department_name,
    p.brand_id,
    b.brand_name,
    p.supplier_id,
    p.base_price,
    p.cost_price,
    p.currency as price_currency,
    p.product_status,
    p.valid_from,
    p.valid_to,
    p.is_current,
    p.version_number
from {{ ref('silver_products_scd2') }} as p
left join {{ ref('silver_categories') }} as c3 on c3.category_id = p.category_id
left join {{ ref('silver_categories') }} as c2 on c2.category_id = c3.parent_category_id
left join {{ ref('silver_categories') }} as c1 on c1.category_id = c2.parent_category_id
left join {{ ref('silver_brands') }} as b on b.brand_id = p.brand_id

union all

select
    'UNKNOWN', null, null, null, null, 'Unknown', 'Unknown', 'Unknown', null, null, null, null, null,
    null, null, '1900-01-01 00:00:00 +00:00'::timestamp_tz, null, true, 1
