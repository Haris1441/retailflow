-- REJECT checks for BigQuery return deliveries against TRUSTED current order lines.
-- Return 60002 asks for 99 units from a line that sold fewer (BATCH_005).
with versions as (
    select source_record_id, business_key, batch_id, order_item_id, return_quantity
    from {{ ref('stg_bq_returns') }}
    where source_operation <> 'DELETE'
),

trusted_lines as (
    select order_item_id, quantity
    from {{ ref('int_bq_order_items__versions') }}
    where disposition = 'ACCEPTED'
),

failures as (
    select 'BIGQUERY' as source_system, 'returns' as entity, v.source_record_id, v.business_key, v.batch_id,
           'RET_MISSING_LINE' as rule_id, 'REJECT' as severity,
           'order_item_id=' || coalesce(v.order_item_id::varchar, 'null') as observed_value
    from versions as v
    left join trusted_lines as l on l.order_item_id = v.order_item_id
    where l.order_item_id is null

    union all

    select 'BIGQUERY', 'returns', v.source_record_id, v.business_key, v.batch_id,
           'RET_QUANTITY_INVALID', 'REJECT',
           'returned=' || coalesce(v.return_quantity::varchar, 'null') || ', sold=' || l.quantity::varchar
    from versions as v
    join trusted_lines as l on l.order_item_id = v.order_item_id
    where v.return_quantity is null
       or v.return_quantity <= 0
       or v.return_quantity > l.quantity
)

{{ dq_with_waivers() }}
