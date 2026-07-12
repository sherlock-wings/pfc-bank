{{ config(location=data_path('dashboard_mart/rpt_daily_overunder.parquet')) }}

with daily_expense as (
    select posted_at_timestamp::date as posted_date
          ,sum(amount_spent) as daily_spend 
    from {{ ref('rpt_expenses_detail')}}
    group by all
)

select b.calendar_date
      ,try_cast(b.daily_income as decimal(12,2)) as daily_income 
      ,try_cast(a.daily_spend as decimal(12,2)) as daily_spend 
      ,try_cast(
        case 
          when round(b.daily_income - a.daily_spend, 2) > 0.00
          then round(b.daily_income - a.daily_spend, 2)
          else 0.00
        end as decimal(12,2)
       ) as dollars_over
      ,try_cast(
        case 
          when round(b.daily_income - a.daily_spend, 2) < 0.00
          then round(b.daily_income - a.daily_spend, 2)
          else 0.00
        end as decimal(12,2)
       ) as dollars_under
      ,case
         when round(b.daily_income - a.daily_spend, 2) > 25.00
         then 'Green'
         when round(b.daily_income - a.daily_spend, 2) < -25.00
         then 'Red'
         when round(b.daily_income - a.daily_spend, 2) between -25.00 and 25.00
         then 'Grey'
         else 'Black'
       end as day_color 
from daily_expense a
right join {{ ref('fact_daily_pay') }} b 
        on a.posted_date =  b.calendar_date
order by 1