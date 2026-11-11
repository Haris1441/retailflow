-- Calendar dimension, one row per UTC date from 2024-01-01 to 2026-12-31.
with days as (
    select dateadd('day', row_number() over (order by seq4()) - 1, '2024-01-01'::date) as date_day
    from table(generator(rowcount => 1096))
)

select
    {{ date_key('date_day') }} as date_key,
    date_day,
    year(date_day) as calendar_year,
    quarter(date_day) as calendar_quarter,
    month(date_day) as calendar_month,
    to_char(date_day, 'YYYY-MM') as year_month,
    date_trunc('month', date_day) as month_start,
    weekiso(date_day) as iso_week,
    dayofweekiso(date_day) as iso_day_of_week,
    dayname(date_day) as day_name,
    dayofweekiso(date_day) in (6, 7) as is_weekend
from days
