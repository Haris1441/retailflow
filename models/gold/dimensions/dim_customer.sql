-- Customer dimension, SCD Type 2 (Phase 11 history). customer_sk identifies one version;
-- facts store the version valid at order time. 'UNKNOWN' is the governed unknown member.
select
    history_key as customer_sk,
    customer_key,
    source_system,
    customer_id,
    first_name,
    last_name,
    email_normalized,
    customer_status,
    loyalty_tier,
    preferred_language,
    country,
    city,
    postal_code,
    is_deleted,
    valid_from,
    valid_to,
    is_current,
    version_number
from {{ ref('silver_customers_scd2') }}

union all

select
    'UNKNOWN', 'UNKNOWN', 'UNKNOWN', null, null, null, null, null, null, null, null, null, null,
    false, '1900-01-01 00:00:00 +00:00'::timestamp_tz, null, true, 1
