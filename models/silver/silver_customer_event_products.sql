-- Child of silver_customer_events: one row per product in an event's products array.
-- API product IDs map to BigQuery catalog IDs through the api_crosswalk seed.
with flattened as (
    select
        e.event_key,
        e.source_system,
        p.index as product_position,
        p.value:product_id::string as source_product_id,
        lower(trim(p.value:placement::string)) as placement
    from {{ ref('silver_customer_events') }} as e,
    lateral flatten(input => e.event_payload:products) as p
)

select
    f.event_key || ':' || f.product_position::varchar as event_product_key,
    f.event_key,
    f.source_system,
    f.product_position,
    f.source_product_id,
    case
        when f.source_system = 'BIGQUERY' then try_to_number(f.source_product_id)
        else x.target_id
    end as product_id,
    f.placement
from flattened as f
left join {{ ref('api_crosswalk') }} as x
  on x.source_system = f.source_system
 and x.entity = 'product'
 and x.source_id = f.source_product_id
