{#
  scd2_history: build SCD Type 2 rows from trusted version history (Phase 11).

  Call it after a CTE named by `versions` that has one row per trusted delivery
  (disposition not DUPLICATE or REJECTED) with:
    key_column, the tracked and Type 1 columns, passthrough columns,
    version_effective_at, source_available_at, source_record_id, batch_id, source_operation

  The caller writes:  with versions as (...), {{ scd2_history('versions', ...) }}
  so the macro emits CTEs (no leading WITH) and the final SELECT.

  Rules
    - Versions are ordered by business time (version_effective_at), then arrival, then record id.
      A backdated change therefore lands at its business time, not its arrival time.
    - tracked_columns are Type 2: a change starts a new row. Changes only to other columns
      do not create history.
    - type1_columns are Type 1: every row shows the latest trusted value (history is restated).
    - A DELETE tombstone closes the open row at the delete time and creates no row itself.
    - valid_to is exclusive and NULL for the open row. is_current is true only for the open row
      of a key that is not deleted.
#}
{% macro scd2_history(versions, key_column, tracked_columns, type1_columns=[], passthrough_columns=[]) %}
scd2_ordered as (
    select
        v.*,
        hash({{ tracked_columns | join(', ') }}, v.source_operation = 'DELETE') as tracked_hash,
        row_number() over (
            partition by v.{{ key_column }}
            order by v.version_effective_at, v.source_available_at, v.source_record_id
        ) as version_seq
    from {{ versions }} as v
),

scd2_starts as (
    -- Keep a version only when its tracked attributes differ from the previous version.
    select *
    from scd2_ordered
    qualify lag(tracked_hash) over (partition by {{ key_column }} order by version_seq) is distinct from tracked_hash
),

scd2_windows as (
    select
        scd2_starts.*,
        version_effective_at as valid_from,
        lead(version_effective_at) over (partition by {{ key_column }} order by version_seq) as valid_to
    from scd2_starts
),

{% if type1_columns %}
scd2_type1 as (
    -- Latest trusted value of each Type 1 column, restated on every row.
    select
        {{ key_column }},
        {% for column in type1_columns %}{{ column }}{% if not loop.last %},
        {% endif %}{% endfor %}
    from scd2_ordered
    where source_operation <> 'DELETE'
    qualify row_number() over (partition by {{ key_column }} order by version_seq desc) = 1
),
{% endif %}

scd2_rows as (
    select
        md5(w.{{ key_column }} || '|' || w.valid_from::varchar) as history_key,
        w.{{ key_column }},
        {% for column in passthrough_columns %}w.{{ column }},
        {% endfor %}
        {% for column in tracked_columns %}w.{{ column }},
        {% endfor %}
        {% for column in type1_columns %}t.{{ column }},
        {% endfor %}
        w.valid_from,
        w.valid_to,
        w.valid_to is null as is_current,
        w.source_record_id,
        w.batch_id as source_batch_id,
        w.source_available_at
    from scd2_windows as w
    {% if type1_columns %}
    left join scd2_type1 as t
      on t.{{ key_column }} = w.{{ key_column }}
    {% endif %}
    where w.source_operation <> 'DELETE'
)

select
    scd2_rows.*,
    row_number() over (partition by {{ key_column }} order by valid_from) as version_number
from scd2_rows
{% endmacro %}
