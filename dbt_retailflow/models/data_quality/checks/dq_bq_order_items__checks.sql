-- REJECT checks for BigQuery order line deliveries.
-- Order 20 line 58 has quantity 0 with its original amounts retained (BATCH_001).
with versions as (
    select source_record_id, business_key, batch_id, quantity, unit_price, product_id
    from {{ ref('stg_bq_order_items') }}
    where source_operation <> 'DELETE'
),

trusted_products as (
    select product_id
    from {{ ref('int_bq_products__versions') }}
    where disposition = 'ACCEPTED'
),

failures as (
    select 'BIGQUERY' as source_system, 'order_items' as entity, source_record_id, business_key, batch_id,
           'OLI_NONPOSITIVE_QUANTITY' as rule_id, 'REJECT' as severity,
           'quantity=' || coalesce(quantity::varchar, 'null') as observed_value
    from versions
    where quantity is null or quantity <= 0

    union all

    select 'BIGQUERY', 'order_items', source_record_id, business_key, batch_id,
           'OLI_NEGATIVE_PRICE', 'REJECT',
           'unit_price=' || unit_price::varchar
    from versions
    where unit_price < 0

    union all

    select 'BIGQUERY', 'order_items', v.source_record_id, v.business_key, v.batch_id,
           'OLI_MISSING_PRODUCT', 'REJECT',
           'product_id=' || coalesce(v.product_id::varchar, 'null')
    from versions as v
    left join trusted_products as p on p.product_id = v.product_id
    where p.product_id is null
)

{{ dq_with_waivers() }}
