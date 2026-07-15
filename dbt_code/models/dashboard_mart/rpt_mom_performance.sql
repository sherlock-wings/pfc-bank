{{ config(location=data_path('dashboard_mart/rpt_mom_performance.parquet')) }}

with filtered_fact as (
select * from {{ ref('fact_transactions') }}
where day(posted_at_timestamp) <= day(current_date())
-- This filter allows for day-level Month-over-Month metrics
)

,filtered_overunder as (
    select * from {{ ref('rpt_daily_overunder') }}
    where day(calendar_date) <= day(current_date())
-- This filter allows for day-level Month-over-Month metrics
)

,agg_fact as (
select year(posted_at_timestamp) as year
      ,month(posted_at_timestamp) as month
      ,sum(amount) as monthly_balance
from filtered_fact
where txn_description not ilike '%transfer%'
   or (txn_description ilike '%transfer%' 
       and (txn_description ilike '%mortgage%' 
            or txn_description ilike '%cashreward%'
            )
       )
group by 1,2
)
         
,day_colors as (
select year(calendar_date) as year
      ,month(calendar_date) as month
      ,avg(daily_spend) as avg_daily_spend
      ,count(case when day_color = 'Green' then 1 end) as total_green_days
      ,count(case when day_color = 'Red' then 1 end) as total_red_days
      ,count(case when day_color = 'Grey' then 1 end) as total_grey_days
      ,count(case when day_color = 'Black' then 1 end) as total_black_days
from filtered_overunder
group by 1,2
)

,join_tbl as (
select a.year
      ,a.month
      ,a.monthly_balance
      ,b.avg_daily_spend
      ,b.total_green_days
      ,b.total_red_days
      ,b.total_grey_days
      ,b.total_black_days
from agg_fact a 
left join day_colors b 
       on a.year = b.year 
      and a.month = b.month
)

,lag_tbl as (
select year
      ,month
      ,lag(monthly_balance) over (order by year, month) as this_time_last_month_balance
      ,monthly_balance as current_monthly_balance
      ,lag(avg_daily_spend) over (order by year, month) as last_month_avg_daily_spend
      ,avg_daily_spend
      ,lag(total_green_days) over (order by year, month) as last_month_total_green_days
      ,total_green_days
      ,lag(total_red_days) over (order by year, month) as last_month_total_red_days
      ,total_red_days
      ,lag(total_grey_days) over (order by year, month) as last_month_total_grey_days
      ,total_grey_days
      ,lag(total_black_days) over (order by year, month) as last_month_total_black_days
      ,total_black_days
from join_tbl
)

select current_date() as as_of_date
      ,try_cast(year as utinyint) as year 
      ,try_cast(month as utinyint) as month 
      ,try_cast(current_monthly_balance as decimal(12,2)) as current_monthly_balance
      ,try_cast(this_time_last_month_balance as decimal(12,2)) as this_time_last_month_balance
      ,try_cast(round(current_monthly_balance - this_time_last_month_balance,2)as decimal(12,2)) as dollars_mom_balance_delta
      ,case 
         when this_time_last_month_balance <> 0
         then try_cast(round((current_monthly_balance - this_time_last_month_balance)/abs(this_time_last_month_balance),2) as decimal(14,4))
       end as pcnt_mom_balance_delta
      ,try_cast(round(avg_daily_spend) as decimal(12,2)) as avg_daily_spend
      ,try_cast(round(last_month_avg_daily_spend) as decimal(12,2)) as last_month_avg_daily_spend
      ,try_cast(round(avg_daily_spend - last_month_avg_daily_spend,2)as decimal(12,2)) as dollars_mom_avg_daily_spend_delta
      ,case 
         when last_month_avg_daily_spend <> 0
         then try_cast(round((avg_daily_spend - last_month_avg_daily_spend)/abs(last_month_avg_daily_spend),2) as decimal(14,4))
       end as pcnt_mom_avg_daily_spend_delta
      ,try_cast(total_green_days as utinyint) as total_green_days
      ,try_cast(last_month_total_green_days as utinyint) as last_month_total_green_days
      ,try_cast(round(total_green_days - last_month_total_green_days,2)as decimal(12,2)) as mom_total_green_days_change
      ,case 
         when last_month_total_green_days <> 0
         then try_cast(round((total_green_days - last_month_total_green_days)/abs(last_month_total_green_days),2) as decimal(14,4))
       end as pcnt_mom_total_green_days
      ,try_cast(total_red_days as utinyint) as total_red_days
      ,try_cast(last_month_total_red_days as utinyint) as last_month_total_red_days
      ,try_cast(round(total_red_days - last_month_total_red_days,2)as decimal(12,2)) as mom_total_red_days_change
      ,case 
         when last_month_total_red_days <> 0
         then try_cast(round((total_red_days - last_month_total_red_days)/abs(last_month_total_red_days),2) as decimal(14,4))
       end as pcnt_mom_total_red_days
      ,try_cast(total_grey_days as utinyint) as total_grey_days
      ,try_cast(last_month_total_grey_days as utinyint) as last_month_total_grey_days
      ,try_cast(round(total_grey_days - last_month_total_grey_days,2)as decimal(12,2)) as mom_total_grey_days_change
      ,case 
         when last_month_total_grey_days <> 0
         then try_cast(round((total_grey_days - last_month_total_grey_days)/abs(last_month_total_grey_days),2) as decimal(14,4))
       end as pcnt_mom_total_grey_days
      ,try_cast(total_black_days as utinyint) as total_black_days
      ,try_cast(last_month_total_black_days as utinyint) as last_month_total_black_days
      ,try_cast(round(total_black_days - last_month_total_black_days,2)as decimal(12,2)) as mom_total_black_days_change
      ,case 
         when last_month_total_black_days <> 0
         then try_cast(round((total_black_days - last_month_total_black_days)/abs(last_month_total_black_days),2) as decimal(14,4))
       end as pcnt_mom_total_black_days
from lag_tbl
