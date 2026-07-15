with filtered_fact as (
select * from fact_transactions
where day(posted_at_timestamp) <= day(current_date())
-- This filter allows for day-level Month-over-Month metrics
)

,filtered_overunder as (
    select * from rpt_daily_overunder
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

select year
      ,month
      ,current_monthly_balance
      ,this_time_last_month_balance
      ,try_cast(round(current_monthly_balance - this_time_last_month_balance,2)as decimal(12,2)) as dollars_mom_balance_delta
      ,case 
         when this_time_last_month_balance <> 0
         then try_cast(round((avg_daily_spend - this_time_last_month_balance)/this_time_last_month_balance,2) as decimal(12,2))
       end as pcnt_mom_balance_delta
      ,avg_daily_spend
      ,last_month_avg_daily_spend
      ,try_cast(round(avg_daily_spend - last_month_avg_daily_spend,2)as decimal(12,2)) as dollars_mom_avg_daily_spend_delta
      ,case 
         when last_month_avg_daily_spend <> 0
         then try_cast(round((avg_daily_spend - last_month_avg_daily_spend)/last_month_avg_daily_spend,2) as decimal(12,4))
       end as pcnt_mom_avg_daily_spend_delta
      ,case 
         when last_month_total_green_days <> 0
         then try_cast(round((total_green_days - last_month_total_green_days)/last_month_total_green_days,2) as decimal(12,2))
       end as pcnt_mom_total_green_days_delta
      ,case 
         when last_month_total_red_days <> 0
         then try_cast(round((total_red_days - last_month_total_red_days)/last_month_total_red_days,2) as decimal(12,2))
       end as pcnt_mom_total_red_days_delta
      ,case 
         when last_month_total_grey_days <> 0
         then try_cast(round((total_grey_days - last_month_total_grey_days)/last_month_total_grey_days,2) as decimal(12,2))
       end as pcnt_mom_total_grey_days_delta
      ,case 
         when last_month_total_black_days <> 0
         then try_cast(round((total_black_days - last_month_total_black_days)/last_month_total_black_days,2) as decimal(12,2))
       end as pcnt_mom_total_black_days_delta
from lag_tbl
order by 1,2;