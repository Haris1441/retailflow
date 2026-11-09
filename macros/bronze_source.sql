{% macro bronze_source(source_system, entity) %}
    select
        source_system,
        entity,
        source_record_id,
        business_key,
        batch_id,
        source_operation,
        source_event_at,
        source_updated_at,
        source_effective_at,
        source_available_at,
        extracted_at,
        ingested_at,
        run_id,
        record_hash,
        raw_payload
    from {{ source('bronze', 'source_records') }}
    where source_system = '{{ source_system }}'
      and entity = '{{ entity }}'
{% endmacro %}

{% macro simple_stage(source_system, entity, key_path) %}
    with source_records as (
        {{ bronze_source(source_system, entity) }}
    )
    select
        source_record_id, business_key, batch_id, source_operation, source_event_at,
        source_updated_at, source_effective_at, source_available_at, ingested_at,
        run_id, record_hash, raw_payload,
        nullif(trim(raw_payload:{{ key_path }}::string), '') as source_business_key
    from source_records
{% endmacro %}
