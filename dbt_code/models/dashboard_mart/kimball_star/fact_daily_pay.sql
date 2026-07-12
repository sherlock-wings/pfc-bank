{{ config(location=data_path('dashboard_mart/kimball_star/fact_daily_pay.parquet')) }}

select a.full_date as calendar_date
      ,a.date_quarter as calendar_quarter
      ,try_cast((b.biweekly_paycheck_posttax_amount*2)/a.total_days_in_month as decimal(12,2)) as daily_income
      ,b.employer_name as from_employer
from {{ ref('dim_date') }} a 
left join {{ ref('stg_payrate') }} b
       on a.full_date between b.effective_start_date 
                          and b.effective_end_date
where a.full_date <= current_date()