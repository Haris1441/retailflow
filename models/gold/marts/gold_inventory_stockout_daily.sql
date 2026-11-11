-- KPI: stockout rate per snapshot date and store market. Snapshots with on hand minus reserved
-- equal to zero, divided by valid observed snapshots.
select
    i.snapshot_date_key as date_key,
    i.snapshot_date,
    st.country,
    count(*) as snapshots,
    count_if(i.is_stockout) as stockout_snapshots,
    count_if(i.is_stockout) / nullif(count(*), 0) as stockout_rate,
    count_if(i.is_below_reorder_level) as below_reorder_level_snapshots
from {{ ref('fct_inventory_snapshot') }} as i
join {{ ref('dim_store') }} as st on st.store_sk = i.store_sk
group by 1, 2, 3
