-- One row per reconciliation check, end to end. The test assert_reconciliation_passes fails the
-- build if any check fails; the detail models show which rows broke.
-- Every check always has a row, even with 0 items (step 0 has none until the first file lands).
with checks as (
    select column1 as step, column2 as layer, column3 as check_name, column4 as detail_model
    from values
        (0, 'Landed file -> Bronze', 'Every loaded file matches its control file and its audited Bronze run', 'recon_landing_to_bronze'),
        (1, 'Source -> Bronze', 'Rows per source, entity and batch match the manifest', 'recon_source_to_bronze'),
        (2, 'Bronze <-> load audit', 'Every Bronze row belongs to an audited run with matching inserted_count', 'recon_bronze_load_audit'),
        (3, 'Bronze -> Silver', 'Every Bronze delivery has exactly one disposition', 'recon_bronze_to_silver'),
        (4, 'Silver -> Gold', 'Silver rows = Gold rows + registered exclusions', 'recon_silver_to_gold'),
        (5, 'Silver -> Gold', 'Silver amounts = Gold amounts + excluded amounts, per currency', 'recon_financial'),
        (6, 'Gold -> marts', 'KPI marts add up to the facts', 'recon_gold_to_marts')
),

results as (
    select 0 as step, status from {{ ref('recon_landing_to_bronze') }}
    union all
    select 1, status from {{ ref('recon_source_to_bronze') }}
    union all
    select 2, status from {{ ref('recon_bronze_load_audit') }}
    union all
    select 3, status from {{ ref('recon_bronze_to_silver') }}
    union all
    select 4, status from {{ ref('recon_silver_to_gold') }}
    union all
    select 5, status from {{ ref('recon_financial') }}
    union all
    select 6, status from {{ ref('recon_gold_to_marts') }}
)

select
    c.step,
    c.layer,
    c.check_name,
    c.detail_model,
    count(r.status) as items_checked,
    count_if(r.status = 'FAIL') as items_failed,
    iff(count_if(r.status = 'FAIL') = 0, 'PASS', 'FAIL') as status
from checks as c
left join results as r
  on r.step = c.step
group by 1, 2, 3, 4
