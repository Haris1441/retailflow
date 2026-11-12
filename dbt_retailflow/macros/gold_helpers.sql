{#- Phase 12 Gold helpers. Reporting dates are UTC calendar dates (business_rules.md). -#}

{% macro utc_date(timestamp_expr) -%}
    to_date(convert_timezone('UTC', {{ timestamp_expr }}))
{%- endmacro %}

{% macro date_key(date_expr) -%}
    to_number(to_char({{ date_expr }}, 'YYYYMMDD'))
{%- endmacro %}

{#- Point-in-time join to an SCD Type 2 dimension: the row valid at event_expr.
    The first version also covers events before it, so every event finds exactly one row. -#}
{% macro as_of(dim_alias, event_expr) -%}
    ({{ event_expr }} >= {{ dim_alias }}.valid_from or {{ dim_alias }}.version_number = 1)
    and ({{ event_expr }} < {{ dim_alias }}.valid_to or {{ dim_alias }}.valid_to is null)
{%- endmacro %}
