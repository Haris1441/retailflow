-- Layer 3 · Silver -> Gold, record counts. For each entity:
--   silver_rows = gold_rows + excluded_rows   (excluded rows are listed in recon_gold_exclusions)
with excluded as (
    select entity, count(*) as excluded_rows
    from {{ ref('recon_gold_exclusions') }}
    group by entity
),

flows as (
    select 'orders' as entity,
           (select count(*) from {{ ref('silver_orders') }}) as silver_rows,
           (select count(distinct order_key) from {{ ref('fct_sales') }}) as gold_rows,
           'fct_sales (distinct orders)' as gold_object
    union all
    select 'order_lines',
           (select count(*) from {{ ref('silver_order_items') }}),
           (select count(*) from {{ ref('fct_sales') }}),
           'fct_sales'
    union all
    select 'payments',
           (select count(*) from {{ ref('silver_payments') }}),
           (select count(*) from {{ ref('fct_payments') }}),
           'fct_payments'
    union all
    select 'returns',
           (select count(*) from {{ ref('silver_returns') }}),
           (select count(*) from {{ ref('fct_returns') }}),
           'fct_returns'
    union all
    select 'inventory',
           (select count(*) from {{ ref('silver_inventory') }}),
           (select count(*) from {{ ref('fct_inventory_snapshot') }}),
           'fct_inventory_snapshot'
    union all
    select 'customers',
           (select count(*) from {{ ref('silver_customers') }}),
           (select count(*) from {{ ref('dim_customer') }} where is_current and customer_key <> 'UNKNOWN'),
           'dim_customer (current versions)'
    union all
    select 'products',
           (select count(*) from {{ ref('silver_products') }}),
           (select count(*) from {{ ref('dim_product') }} where is_current and product_id is not null),
           'dim_product (current versions)'
)

select
    f.entity,
    f.gold_object,
    f.silver_rows,
    f.gold_rows,
    coalesce(e.excluded_rows, 0) as excluded_rows,
    f.silver_rows - f.gold_rows - coalesce(e.excluded_rows, 0) as difference,
    iff(f.silver_rows = f.gold_rows + coalesce(e.excluded_rows, 0), 'PASS', 'FAIL') as status
from flows as f
left join excluded as e on e.entity = f.entity
