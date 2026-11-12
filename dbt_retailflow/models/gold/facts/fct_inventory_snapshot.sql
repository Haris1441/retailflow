-- FCT_INVENTORY_SNAPSHOT: one store, product and snapshot date. Available stock is on hand minus
-- reserved; a stockout is zero available stock. The product version is the one valid on the
-- snapshot date. The rejected BATCH_005 negative-stock change is not here (Phase 9 fallback).
select
    i.inventory_key,
    i.source_system,
    coalesce(i.store_id, -1) as store_sk,
    i.product_id,
    coalesce(p.product_sk, 'UNKNOWN') as product_sk,
    {{ date_key('i.snapshot_date') }} as snapshot_date_key,
    i.snapshot_date,
    i.quantity_on_hand,
    i.reserved_quantity,
    i.quantity_on_hand - i.reserved_quantity as available_quantity,
    i.reorder_level,
    i.quantity_on_hand - i.reserved_quantity = 0 as is_stockout,
    i.quantity_on_hand - i.reserved_quantity < i.reorder_level as is_below_reorder_level
from {{ ref('silver_inventory') }} as i
left join {{ ref('dim_product') }} as p
  on p.product_id = i.product_id
 and {{ as_of('p', "to_timestamp_tz(i.snapshot_date::varchar || ' 00:00:00 +00:00')") }}
