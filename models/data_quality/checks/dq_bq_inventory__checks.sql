-- REJECT checks for BigQuery inventory snapshot deliveries.
with failures as (
    select 'BIGQUERY' as source_system, 'inventory' as entity, source_record_id, business_key, batch_id,
           'INV_NEGATIVE_QUANTITY' as rule_id, 'REJECT' as severity,
           'on_hand=' || coalesce(quantity_on_hand::varchar, 'null')
             || ', reserved=' || coalesce(reserved_quantity::varchar, 'null') as observed_value
    from {{ ref('stg_bq_inventory') }}
    where source_operation <> 'DELETE'
      and (quantity_on_hand < 0 or reserved_quantity < 0)
)

{{ dq_with_waivers() }}
