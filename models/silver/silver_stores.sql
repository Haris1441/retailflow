-- One current row per store. Store 2 (US WEB) also receives the API storefront's orders
-- through the api_crosswalk seed.
select
    store_id,
    store_name,
    store_type,
    country,
    region,
    city,
    currency,
    channel,
    opening_date,
    store_status,
    store_updated_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_stores__versions') }}
where disposition = 'ACCEPTED'
