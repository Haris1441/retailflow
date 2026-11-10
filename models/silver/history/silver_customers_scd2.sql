-- SCD Type 2 customer history (Phase 11). One row per period in which the tracked attributes
-- were constant, valid from valid_from (inclusive) to valid_to (exclusive, NULL = open).
--
-- Type 2 (new row on change): email, status, loyalty tier, preferred language, location, is_deleted
-- Type 1 (latest value on every row): name, phone, gender, birth and registration dates
-- Not tracked: the nested addresses array (it has its own table) and audit timestamps.
--
-- Built from trusted version history, not from snapshots of the current table, so it is fully
-- reproducible and places the backdated BATCH_006 loyalty change for customer 12 at its
-- business date. Rejected and duplicate deliveries never create history.
with versions as (
    select
        'BIGQUERY:' || customer_id::varchar as customer_key,
        source_system,
        customer_id::varchar as customer_id,
        email_normalized,
        customer_status,
        loyalty_tier,
        preferred_language,
        country,
        city,
        address,
        postal_code,
        is_deleted,
        first_name,
        last_name,
        phone,
        gender,
        birth_date,
        registration_date,
        version_effective_at,
        source_available_at,
        source_record_id,
        batch_id,
        source_operation
    from {{ ref('int_bq_customers__versions') }}
    where disposition not in ('DUPLICATE', 'REJECTED')

    union all

    select
        'MOCK_API:' || customer_id,
        source_system,
        customer_id,
        email_normalized,
        null::varchar,
        null::varchar,
        null::varchar,
        null::varchar,
        null::varchar,
        null::varchar,
        null::varchar,
        false,
        null::varchar,
        null::varchar,
        null::varchar,
        null::varchar,
        null::date,
        null::date,
        version_effective_at,
        source_available_at,
        source_record_id,
        batch_id,
        source_operation
    from {{ ref('int_api_customers__versions') }}
    where disposition not in ('DUPLICATE', 'REJECTED')
),

{{ scd2_history(
    'versions',
    key_column='customer_key',
    passthrough_columns=['source_system', 'customer_id'],
    tracked_columns=[
        'email_normalized',
        'customer_status',
        'loyalty_tier',
        'preferred_language',
        'country',
        'city',
        'address',
        'postal_code',
        'is_deleted'
    ],
    type1_columns=[
        'first_name',
        'last_name',
        'phone',
        'gender',
        'birth_date',
        'registration_date'
    ]
) }}
