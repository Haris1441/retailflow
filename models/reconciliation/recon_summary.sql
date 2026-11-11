-- One row per reconciliation check, end to end. The test assert_reconciliation_passes fails the
-- build if any check fails; the detail models show which rows broke.
with results as (
    select 1 as step, 'Source -> Bronze' as layer, 'Rows per source, entity and batch match the manifest' as check_name,
           'recon_source_to_bronze' as detail_model, status from {{ ref('recon_source_to_bronze') }}
    union all
    select 2, 'Bronze <-> load audit', 'Every Bronze row belongs to an audited run with matching inserted_count',
           'recon_bronze_load_audit', status from {{ ref('recon_bronze_load_audit') }}
    union all
    select 3, 'Bronze -> Silver', 'Every Bronze delivery has exactly one disposition',
           'recon_bronze_to_silver', status from {{ ref('recon_bronze_to_silver') }}
    union all
    select 4, 'Silver -> Gold', 'Silver rows = Gold rows + registered exclusions',
           'recon_silver_to_gold', status from {{ ref('recon_silver_to_gold') }}
    union all
    select 5, 'Silver -> Gold', 'Silver amounts = Gold amounts + excluded amounts, per currency',
           'recon_financial', status from {{ ref('recon_financial') }}
    union all
    select 6, 'Gold -> marts', 'KPI marts add up to the facts',
           'recon_gold_to_marts', status from {{ ref('recon_gold_to_marts') }}
)

select
    step,
    layer,
    check_name,
    detail_model,
    count(*) as items_checked,
    count_if(status = 'FAIL') as items_failed,
    iff(count_if(status = 'FAIL') = 0, 'PASS', 'FAIL') as status
from results
group by 1, 2, 3, 4
