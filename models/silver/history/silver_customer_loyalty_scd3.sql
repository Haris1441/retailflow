-- SCD Type 3 loyalty tier (Phase 11): one row per current customer with the current tier,
-- the tier before it, and when the current tier started. Type 3 keeps exactly one prior value
-- in extra columns, so a second change overwrites the first "previous" value.
--
-- Derived from the Type 2 history: consecutive periods with the same tier (for example a row
-- created by an email change) are not tier changes.
with tier_periods as (
    select
        customer_key,
        loyalty_tier,
        valid_from,
        lag(loyalty_tier) over (partition by customer_key order by valid_from) as prior_tier,
        version_number
    from {{ ref('silver_customers_scd2') }}
),

tier_changes as (
    select customer_key, loyalty_tier, prior_tier, valid_from
    from tier_periods
    where version_number = 1
       or loyalty_tier is distinct from prior_tier
),

latest_change as (
    select *
    from tier_changes
    qualify row_number() over (partition by customer_key order by valid_from desc) = 1
)

select
    c.customer_key,
    c.source_system,
    c.customer_id,
    c.loyalty_tier as current_loyalty_tier,
    l.prior_tier as previous_loyalty_tier,
    l.valid_from as loyalty_tier_since,
    l.prior_tier is not null as has_tier_change
from {{ ref('silver_customers') }} as c
left join latest_change as l
  on l.customer_key = c.customer_key
