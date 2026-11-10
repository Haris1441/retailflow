-- Phase 11: SCD Type 2 integrity for customers and products. Expect zero rows.
--   1. Periods are positive: valid_from < valid_to.
--   2. Periods are contiguous: each closed row ends exactly where the next row starts.
--   3. Every current Silver (Type 1) row has exactly one current history row.
--   4. The current history row agrees with the current Silver row on the tracked attributes.
with customer_periods as (
    select
        'customers' as entity,
        customer_key as entity_key,
        valid_from,
        valid_to,
        is_current,
        lead(valid_from) over (partition by customer_key order by valid_from) as next_valid_from
    from {{ ref('silver_customers_scd2') }}
),

product_periods as (
    select
        'products',
        product_id::varchar,
        valid_from,
        valid_to,
        is_current,
        lead(valid_from) over (partition by product_id order by valid_from)
    from {{ ref('silver_products_scd2') }}
),

periods as (
    select * from customer_periods
    union all
    select * from product_periods
),

period_errors as (
    select entity, entity_key, 'non-positive period' as problem
    from periods
    where valid_to is not null and valid_to <= valid_from
    union all
    select entity, entity_key, 'gap or overlap with next period'
    from periods
    where next_valid_from is not null and valid_to is distinct from next_valid_from
),

current_counts as (
    select 'customers' as entity, c.customer_key as entity_key, count(h.customer_key) as current_rows
    from {{ ref('silver_customers') }} as c
    left join {{ ref('silver_customers_scd2') }} as h
      on h.customer_key = c.customer_key and h.is_current
    group by 1, 2
    union all
    select 'products', p.product_id::varchar, count(h.product_id)
    from {{ ref('silver_products') }} as p
    left join {{ ref('silver_products_scd2') }} as h
      on h.product_id = p.product_id and h.is_current
    group by 1, 2
),

current_errors as (
    select entity, entity_key, 'expected one current row, found ' || current_rows::varchar
    from current_counts
    where current_rows <> 1
),

attribute_errors as (
    select 'customers', c.customer_key, 'current row differs from silver_customers'
    from {{ ref('silver_customers') }} as c
    join {{ ref('silver_customers_scd2') }} as h
      on h.customer_key = c.customer_key and h.is_current
    where h.loyalty_tier is distinct from c.loyalty_tier
       or h.email_normalized is distinct from c.email_normalized
       or h.customer_status is distinct from c.customer_status
       or h.address is distinct from c.address
       or h.is_deleted is distinct from c.is_deleted
       or h.first_name is distinct from c.first_name
    union all
    select 'products', p.product_id::varchar, 'current row differs from silver_products'
    from {{ ref('silver_products') }} as p
    join {{ ref('silver_products_scd2') }} as h
      on h.product_id = p.product_id and h.is_current
    where h.base_price is distinct from p.base_price
       or h.category_id is distinct from p.category_id
       or h.product_name is distinct from p.product_name
)

select * from period_errors
union all
select * from current_errors
union all
select * from attribute_errors
