{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
      RetailFlow uses one approved learning-environment schema for each layer.
      Returning the configured custom schema prevents dbt Cloud's default
      development-schema prefix from turning STAGING into DBT_USER_STAGING.
    #}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
