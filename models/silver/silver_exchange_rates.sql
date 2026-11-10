-- One resolved rate per date and currency pair. The BATCH_006 PKR correction shares the
-- original's business time (the rate date) and wins on later availability.
select
    rate_date::varchar || ':' || from_currency || ':' || to_currency as exchange_rate_key,
    rate_date,
    from_currency,
    to_currency,
    exchange_rate,
    rate_effective_at,
    {{ silver_lineage() }}
from {{ ref('int_bq_exchange_rates__versions') }}
where disposition = 'ACCEPTED'
