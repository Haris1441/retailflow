{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
      Where each model is built.

      Production and the normal development build: one fixed schema per layer (STAGING, SILVER,
      DATA_QUALITY, GOLD). Returning the custom schema as is stops dbt Cloud's development prefix
      from turning STAGING into DBT_USER_STAGING.

      Phase 15, isolated builds, so unreviewed code never overwrites the real layer tables:
      - dbt Cloud CI jobs build a pull request in a schema named dbt_cloud_pr_<job>_<pr>.
        Every layer goes under that prefix: dbt_cloud_pr_123_45_SILVER, ..._GOLD.
      - Anyone can isolate a build by setting RETAILFLOW_SCHEMA_PREFIX, for example to
        DEV_SAAD, which builds DEV_SAAD_SILVER, DEV_SAAD_GOLD and so on.
      Sources (BRONZE, AUDIT, CONTROL) are read-only and never prefixed.
    #}
    {%- set prefix = env_var('RETAILFLOW_SCHEMA_PREFIX', '') | trim -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.schema.lower().startswith('dbt_cloud_pr_') -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- elif prefix -%}
        {{ prefix }}_{{ custom_schema_name | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
