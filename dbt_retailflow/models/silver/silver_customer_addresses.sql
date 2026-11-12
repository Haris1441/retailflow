-- Child of silver_customers: one row per customer and address ID.
-- Flattened from the current customer version only (BATCH_007 adds two addresses each to 10 customers).
select
    v.customer_key || ':' || a.value:address_id::string as customer_address_key,
    v.customer_key,
    v.customer_id,
    a.value:address_id::string as address_id,
    nullif(trim(a.value:street::string), '') as street,
    nullif(trim(a.value:city::string), '') as city,
    upper(trim(a.value:country::string)) as country,
    coalesce(try_to_boolean(a.value:is_primary::string), false) as is_primary,
    v.source_record_id,
    v.source_batch_id
from (
    select
        'BIGQUERY:' || customer_id::varchar as customer_key,
        customer_id::varchar as customer_id,
        addresses,
        source_record_id,
        batch_id as source_batch_id
    from {{ ref('int_bq_customers__versions') }}
    where disposition = 'ACCEPTED'
      and addresses is not null
) as v,
lateral flatten(input => v.addresses) as a
