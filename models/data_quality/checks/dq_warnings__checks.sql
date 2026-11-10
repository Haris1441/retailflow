-- WARN checks on CURRENT Silver rows. Warnings never stop a record becoming current;
-- they are reported so owners can fix the source. Evaluated after version selection
-- because some (shared email) only make sense across the current set.
with current_emails as (
    select email_normalized, count(*) as customers_using
    from {{ ref('silver_customers') }}
    where email_normalized is not null
    group by email_normalized
),

failures as (
    select source_system, 'customers' as entity, source_record_id, customer_id as business_key,
           source_batch_id as batch_id, 'CUS_MISSING_EMAIL' as rule_id, 'WARN' as severity,
           'email is null or blank' as observed_value
    from {{ ref('silver_customers') }}
    where email_normalized is null

    union all

    select source_system, 'customers', source_record_id, customer_id, source_batch_id,
           'CUS_MALFORMED_EMAIL', 'WARN', email_normalized
    from {{ ref('silver_customers') }}
    where email_normalized is not null
      and not regexp_like(email_normalized, '[^@ ]+@[^@ ]+\\.[^@ ]+')

    union all

    select c.source_system, 'customers', c.source_record_id, c.customer_id, c.source_batch_id,
           'CUS_SHARED_EMAIL', 'WARN', c.email_normalized || ' used by ' || e.customers_using || ' customers'
    from {{ ref('silver_customers') }} as c
    join current_emails as e on e.email_normalized = c.email_normalized
    where e.customers_using > 1

    union all

    select 'BIGQUERY', 'products', source_record_id, product_id::varchar, source_batch_id,
           'PRD_MISSING_DESCRIPTION', 'WARN', 'description is null'
    from {{ ref('silver_products') }}
    where description is null

    union all

    select 'BIGQUERY', 'suppliers', source_record_id, supplier_id::varchar, source_batch_id,
           'SUP_MISSING_CONTACT', 'WARN', 'contact_email is null'
    from {{ ref('silver_suppliers') }}
    where contact_email is null
)

{{ dq_with_waivers() }}
