-- REJECT checks for BigQuery category deliveries.
-- Each delivery is checked against the category tree AS OF its own business time: every other
-- category's latest version at or before that time. This blames the change that closes a cycle
-- (category 1 -> parent 7 in BATCH_005: 7 -> 4 -> 1) and not the older categories it loops through.
-- The tree is at most a few levels deep, so eight explicit hops cover any cycle.
with versions as (
    select
        source_record_id,
        business_key,
        batch_id,
        category_id,
        parent_category_id,
        coalesce(source_effective_at, source_updated_at, source_available_at) as version_effective_at,
        source_available_at
    from {{ ref('stg_bq_categories') }}
    where source_operation <> 'DELETE'
),

tree_as_of as (
    select
        candidate.source_record_id as candidate_record_id,
        other.category_id,
        other.parent_category_id
    from versions as candidate
    join versions as other
      on other.category_id <> candidate.category_id
     and other.version_effective_at <= candidate.version_effective_at
    qualify row_number() over (
        partition by candidate.source_record_id, other.category_id
        order by other.version_effective_at desc, other.source_available_at desc, other.source_record_id desc
    ) = 1
),

walk as (
    select
        v.*,
        h1.category_id is not null as parent_exists,
        h1.parent_category_id as hop_2,
        h2.parent_category_id as hop_3,
        h3.parent_category_id as hop_4,
        h4.parent_category_id as hop_5,
        h5.parent_category_id as hop_6,
        h6.parent_category_id as hop_7,
        h7.parent_category_id as hop_8
    from versions as v
    left join tree_as_of as h1 on h1.candidate_record_id = v.source_record_id and h1.category_id = v.parent_category_id
    left join tree_as_of as h2 on h2.candidate_record_id = v.source_record_id and h2.category_id = h1.parent_category_id
    left join tree_as_of as h3 on h3.candidate_record_id = v.source_record_id and h3.category_id = h2.parent_category_id
    left join tree_as_of as h4 on h4.candidate_record_id = v.source_record_id and h4.category_id = h3.parent_category_id
    left join tree_as_of as h5 on h5.candidate_record_id = v.source_record_id and h5.category_id = h4.parent_category_id
    left join tree_as_of as h6 on h6.candidate_record_id = v.source_record_id and h6.category_id = h5.parent_category_id
    left join tree_as_of as h7 on h7.candidate_record_id = v.source_record_id and h7.category_id = h6.parent_category_id
),

failures as (
    select 'BIGQUERY' as source_system, 'categories' as entity, source_record_id, business_key, batch_id,
           'CAT_PARENT_CYCLE' as rule_id, 'REJECT' as severity,
           'category ' || category_id || ' parent ' || parent_category_id as observed_value
    from walk
    where category_id = parent_category_id
       or category_id in (hop_2, hop_3, hop_4, hop_5, hop_6, hop_7, hop_8)

    union all

    select 'BIGQUERY', 'categories', source_record_id, business_key, batch_id,
           'CAT_MISSING_PARENT', 'REJECT',
           'parent ' || parent_category_id
    from walk
    where parent_category_id is not null
      and parent_category_id <> category_id
      and not parent_exists
)

{{ dq_with_waivers() }}
