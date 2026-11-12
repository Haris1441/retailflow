{#- Lineage columns every Silver table carries back to its winning Bronze delivery. -#}
{% macro silver_lineage() -%}
    source_record_id,
    batch_id as source_batch_id,
    version_effective_at,
    version_count,
    has_version_tie
{%- endmacro %}
