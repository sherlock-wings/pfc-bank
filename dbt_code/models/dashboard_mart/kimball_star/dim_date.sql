{{ config(location=data_path('dashboard_mart/kimball_star/dim_date.parquet')
         )
}}

with init_spine as (
{{ dbt_utils.date_spine(
    datepart="day",
    start_date="cast('2026-01-01' as date)",
    end_date="cast('2099-12-31' as date)"
) }}   
)


select date_day::date as full_date
      ,try_cast(year(date_day) as utinyint) as date_year
      ,try_cast(quarter(date_day) as utinyint) as date_quarter
      ,try_cast(month(date_day) as utinyint) as date_month
      ,case
         when month(date_day) = 1  then 'January'
         when month(date_day) = 2  then 'February'
         when month(date_day) = 3  then 'March'
         when month(date_day) = 4  then 'April'
         when month(date_day) = 5  then 'May'
         when month(date_day) = 6  then 'June'
         when month(date_day) = 7  then 'July'
         when month(date_day) = 8  then 'August'
         when month(date_day) = 9  then 'September'
         when month(date_day) = 10 then 'October'
         when month(date_day) = 11 then 'November'
         when month(date_day) = 12 then 'December'
       end as name_date_month  
      ,try_cast(days_in_month(date_day) as utinyint) as total_days_in_month
      ,try_cast(week(date_day) as utinyint) as date_week
      ,try_cast(isodow(date_day) as utinyint) day_of_week
      ,case
         when isodow(date_day) = 1 then 'Monday'
         when isodow(date_day) = 2 then 'Tuesday'
         when isodow(date_day) = 3 then 'Wednesday'
         when isodow(date_day) = 4 then 'Thursday'
         when isodow(date_day) = 5 then 'Friday'
         when isodow(date_day) = 6 then 'Saturday'
         when isodow(date_day) = 7 then 'Sunday'
       end as name_day_of_week
      ,case 
         when isodow(date_day) in (6,7)
         then true
         else false
       end as is_weekend_ind
from init_spine
         
