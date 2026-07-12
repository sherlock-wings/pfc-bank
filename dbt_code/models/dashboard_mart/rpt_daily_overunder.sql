{{ config(location=data_path('dashboard_mart/rpt_daily_overunder.parquet')) }} 

with daily_expense as (
    select posted_at_timestamp::date as posted_date
          ,sum(amount_spent) as daily_spend 
    from {{ ref('rpt_expenses_detail')}}
    group by all
)

select b.calendar_date
      ,try_cast(coalesce(b.daily_income, 0.00) as decimal(12,2)) as daily_income
      ,try_cast(coalesce(a.daily_spend, 0.00) as decimal(12,2)) as daily_spend 
      ,try_cast(
        case 
          when b.daily_income - a.daily_spend > 0.00
          then b.daily_income - a.daily_spend
          else 0.00
        end as decimal(12,2)
       ) as dollars_over
      ,try_cast(
        case 
          when b.daily_income - a.daily_spend < 0.00
          then b.daily_income - a.daily_spend
          else 0.00
        end as decimal(12,2)
       ) as dollars_under
      ,case
         when coalesce(a.daily_spend,0) = 0
         then 'Green'
         when coalesce(b.daily_income,0) = 0
          and coalesce(b.daily_income,0) <> 0 
         then 'Red'
         when round(a.daily_spend,2) = round(b.daily_income,2) then 'Black'
         when b.daily_income - a.daily_spend > 25.00
         then 'Green'
         when b.daily_income - a.daily_spend < -25.00
         then 'Red'
         when b.daily_income - a.daily_spend between -25.00 and 25.00
         then 'Grey'
       end as day_color 
from daily_expense a
right join {{ ref('fact_daily_pay') }} b 
        on a.posted_date =  b.calendar_date
order by 1