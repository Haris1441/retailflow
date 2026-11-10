-- One row per Bronze delivery (source_system, entity, source_record_id) and its Silver disposition.
-- ACCEPTED   current version of the business key
-- SUPERSEDED an older version replaced by a later one
-- DUPLICATE  an identical copy of an earlier delivery (same key, content and operation)
-- DELETED    the current version is a delete tombstone, so the key has no current row
-- Phase 9 adds REJECTED. Row counts per source_system and entity must equal Bronze.
with deliveries as (
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_api_customers__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_api_events__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_api_inventory__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_api_orders__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_api_payments__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_brands__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_categories__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_customer_events__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_customers__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_exchange_rates__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_inventory__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_order_items__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_order_promotions__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_orders__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_payments__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_products__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_promotions__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_returns__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_stores__versions') }}
    union all
    select source_system, entity, source_record_id, business_key, batch_id, source_operation,
           version_effective_at, source_available_at, content_delivery_rank, version_rank,
           version_count, has_version_tie, disposition
    from {{ ref('int_bq_suppliers__versions') }}
)

select
    source_system || ':' || entity || ':' || source_record_id as delivery_key,
    deliveries.*
from deliveries
