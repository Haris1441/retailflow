-- Store dimension (Type 1): market (country, currency) and channel. store_sk -1 is the unknown member.
select
    store_id as store_sk,
    store_id,
    store_name,
    store_type,
    country,
    region,
    city,
    currency,
    channel,
    store_status
from {{ ref('silver_stores') }}

union all

select -1, null, 'Unknown', null, 'UNKNOWN', null, null, null, 'UNKNOWN', null
