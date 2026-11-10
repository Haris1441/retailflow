-- One row per failed rule per delivery (failure_key). Multiple failures on one delivery are
-- stored separately. REJECT results cover every delivery; WARN results cover current rows.
with all_failures as (
    select * from {{ ref('dq_bq_categories__checks') }}
    union all select * from {{ ref('dq_bq_products__checks') }}
    union all select * from {{ ref('dq_bq_inventory__checks') }}
    union all select * from {{ ref('dq_bq_order_items__checks') }}
    union all select * from {{ ref('dq_bq_orders__checks') }}
    union all select * from {{ ref('dq_bq_returns__checks') }}
    union all select * from {{ ref('dq_api_orders__checks') }}
    union all select * from {{ ref('dq_warnings__checks') }}
)

select
    f.*,
    r.description as rule_description,
    d.disposition as delivery_disposition
from all_failures as f
left join {{ ref('dq_rules') }} as r
  on r.rule_id = f.rule_id
left join {{ ref('silver_record_dispositions') }} as d
  on d.delivery_key = f.delivery_key
