-- REJECT checks for mock API order deliveries. API lines arrive inside the order payload,
-- so line rules and the header balance are checked on the same delivery.
with versions as (
    select source_record_id, business_key, batch_id, customer_id, items,
           order_total, discount_amount, shipping_amount
    from {{ ref('stg_api_orders') }}
    where source_operation <> 'DELETE'
),

items as (
    select
        v.source_record_id,
        try_to_decimal(i.value:line_total::string, 18, 4) as line_total,
        try_to_number(i.value:quantity::string) as quantity,
        i.value:product_id::string as source_product_id
    from versions as v,
    lateral flatten(input => v.items) as i
),

item_summary as (
    select
        it.source_record_id,
        sum(it.line_total) as lines_total,
        count_if(it.quantity is null or it.quantity <= 0 or x.target_id is null) as invalid_lines
    from items as it
    left join {{ ref('api_crosswalk') }} as x
      on x.source_system = 'MOCK_API' and x.entity = 'product' and x.source_id = it.source_product_id
    group by it.source_record_id
),

current_customers as (
    select customer_id
    from {{ ref('int_api_customers__versions') }}
    where disposition = 'ACCEPTED'
),

failures as (
    select 'MOCK_API' as source_system, 'orders' as entity, v.source_record_id, v.business_key, v.batch_id,
           'ORD_MISSING_CUSTOMER' as rule_id, 'REJECT' as severity,
           'customer_id=' || coalesce(v.customer_id, 'null') as observed_value
    from versions as v
    left join current_customers as c on c.customer_id = v.customer_id
    where c.customer_id is null

    union all

    select 'MOCK_API', 'orders', v.source_record_id, v.business_key, v.batch_id,
           'ORD_AMOUNT_MISMATCH', 'REJECT',
           'header=' || coalesce(v.order_total::varchar, 'null')
             || ', expected='
             || (coalesce(s.lines_total, 0) - coalesce(v.discount_amount, 0) + coalesce(v.shipping_amount, 0))::varchar
    from versions as v
    left join item_summary as s on s.source_record_id = v.source_record_id
    where v.order_total is null
       or abs(v.order_total - (coalesce(s.lines_total, 0) - coalesce(v.discount_amount, 0)
                               + coalesce(v.shipping_amount, 0))) > 0.01

    union all

    select 'MOCK_API', 'orders', v.source_record_id, v.business_key, v.batch_id,
           'ORD_API_ITEM_INVALID', 'REJECT',
           'invalid_lines=' || s.invalid_lines::varchar
    from versions as v
    join item_summary as s on s.source_record_id = v.source_record_id
    where s.invalid_lines > 0
)

{{ dq_with_waivers() }}
