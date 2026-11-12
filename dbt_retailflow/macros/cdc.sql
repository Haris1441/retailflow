{#
  Phase 10 · CDC simulation and incremental Silver.

  cdc_visible: the Bronze rows a build may see. The var cdc_through_batch (default BATCH_999,
  meaning everything) hides later BigQuery change batches, so the same Bronze table can be
  replayed batch by batch, as if each batch were arriving for the first time. MOCK_API rows
  are always visible.
#}
{% macro cdc_visible(source_system_expr='source_system', batch_expr='batch_id') -%}
    ({{ source_system_expr }} <> 'BIGQUERY' or {{ batch_expr }} <= '{{ var("cdc_through_batch") }}')
{%- endmacro %}


{#
  incremental_affected_keys: business keys of one source that received a Bronze delivery
  after the target table's watermark.

  The watermark is arrival time (source_available_at), never business time. A late-arriving
  record (BATCH_006 payments are 45 days backdated) has an old business time but a new
  arrival time, so it is still picked up. Every delivery of an affected key is then
  re-resolved, so a late record lands in the right place in the key's history.

  silver_lookback_hours re-reads a window before the watermark. Re-reading is harmless
  because a key is always rebuilt from its full history.
#}
{% macro incremental_affected_keys(staging_relation, source_system) %}
    select business_key
    from {{ staging_relation }}
    where source_available_at > (
        select coalesce(
            dateadd('hour', -{{ var('silver_lookback_hours') }}, max(last_delivery_available_at)),
            '1900-01-01 00:00:00 +00:00'::timestamp_tz
        )
        from {{ this }}
        where source_system = '{{ source_system }}'
    )
{% endmacro %}


{#
  Columns every incremental Silver table carries.
    key_disposition             disposition of the key's top version. Rows other than ACCEPTED
                                are written only so delete+insert replaces the old row, and the
                                post-hook then removes them (deleted or quarantined keys).
    last_delivery_available_at  latest arrival of any delivery of the key; the table watermark
    silver_processed_at         when this row was last rewritten (excluded from content checks)
#}
{% macro silver_incremental_columns() -%}
    disposition as key_disposition,
    last_delivery_available_at,
    '{{ run_started_at }}'::timestamp_tz as silver_processed_at
{%- endmacro %}
