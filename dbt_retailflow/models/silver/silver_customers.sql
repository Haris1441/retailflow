-- One current row per customer per source system (key: source_system:customer_id).
-- BigQuery and the API are separate customer identities; email is a contact attribute,
-- not a match key (source_to_target_mapping.md). Soft-deleted customers stay with is_deleted = true.
with bigquery as (
    select
        'BIGQUERY:' || customer_id::varchar as customer_key,
        source_system,
        customer_id::varchar as customer_id,
        first_name,
        last_name,
        email_normalized,
        phone,
        gender,
        preferred_language,
        birth_date,
        registration_date,
        customer_status,
        loyalty_tier,
        country,
        city,
        address,
        postal_code,
        customer_created_at,
        customer_updated_at,
        is_deleted,
        {{ silver_lineage() }}
    from {{ ref('int_bq_customers__versions') }}
    where disposition = 'ACCEPTED'
),

api as (
    select
        'MOCK_API:' || customer_id as customer_key,
        source_system,
        customer_id,
        null::varchar as first_name,
        null::varchar as last_name,
        email_normalized,
        null::varchar as phone,
        null::varchar as gender,
        null::varchar as preferred_language,
        null::date as birth_date,
        null::date as registration_date,
        null::varchar as customer_status,
        null::varchar as loyalty_tier,
        null::varchar as country,
        null::varchar as city,
        null::varchar as address,
        null::varchar as postal_code,
        customer_created_at,
        customer_updated_at,
        false as is_deleted,
        {{ silver_lineage() }}
    from {{ ref('int_api_customers__versions') }}
    where disposition = 'ACCEPTED'
)

select * from bigquery
union all
select * from api
