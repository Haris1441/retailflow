-- REJECT checks for BigQuery product deliveries.
-- Category existence is checked against TRUSTED current categories.
with versions as (
    select source_record_id, business_key, batch_id, base_price, cost_price, category_id
    from {{ ref('stg_bq_products') }}
    where source_operation <> 'DELETE'
),

trusted_categories as (
    select category_id
    from {{ ref('int_bq_categories__versions') }}
    where disposition = 'ACCEPTED'
),

failures as (
    select 'BIGQUERY' as source_system, 'products' as entity, source_record_id, business_key, batch_id,
           'PRD_NEGATIVE_PRICE' as rule_id, 'REJECT' as severity,
           'base_price=' || coalesce(base_price::varchar, 'null')
             || ', cost_price=' || coalesce(cost_price::varchar, 'null') as observed_value
    from versions
    where base_price < 0 or cost_price < 0

    union all

    select 'BIGQUERY', 'products', v.source_record_id, v.business_key, v.batch_id,
           'PRD_MISSING_CATEGORY', 'REJECT',
           'category_id=' || coalesce(v.category_id::varchar, 'null')
    from versions as v
    left join trusted_categories as c on c.category_id = v.category_id
    where c.category_id is null
)

{{ dq_with_waivers() }}
