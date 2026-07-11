{{ config(location=data_path('dashboard_mart/rpt_monthly_savings.parquet')) }}

with cost as (
select date_trunc('month', posted_at_timestamp)::date as year_month
      ,sum(amount_spent) as total_spend
from {{ ref('rpt_expenses_detail') }}
group by 1
)

,saved as (
select date_trunc('month', posted_at_timestamp)::date as year_month
      ,sum(amount_earned) as total_earned
from {{ ref('rpt_income_detail') }}
group by 1
)


select a.year_month
      ,a.total_spend
      ,b.total_earned
      ,case 
         when round(b.total_earned - a.total_spend, 2) > 0.00
         then round(b.total_earned - a.total_spend, 2)
       else 0.00
       end as dollars_saved
      ,case 
         when b.total_earned > 0
         then cast((b.total_earned - a.total_spend)/b.total_earned as decimal(36,4))
       else 0.0000
       end as pcnt_saved
      ,case 
         when round(b.total_earned - a.total_spend, 2) <= 0.00
         then round(b.total_earned - a.total_spend, 2)
       else 0.0000
       end as dollars_lost
      ,case 
         when b.total_earned > 0
         then cast((b.total_earned - a.total_spend)/b.total_earned as decimal(36,4))
       else 0.0000
       end as pcnt_lost 
from cost a 
join saved b 
  on a.year_month = b.year_month