{{ config(location=data_path('dashboard_mart/rpt_transaction_daily.parquet')) }} 

with money_spine as (
    select calendar_date
           calendar_date - interval 1 month as last_month_date
          ,sum(txn_amount) as eod_balance
    from {{ ref('rpt_transaction_detail')}}
    group by 1 
)

select a.calendar_date
      ,a.eod_balance
      ,b.eod_balance as last_month_eod_balance
      ,b.eod_balance - a.eod_balance as mom_dollars_change
      ,case 
         when b.eod_balance <> 0
         then try_cast(round((a.eod_balance - b.eod_balance)/abs(b.eod_balance),4) as decimal (14,4))
       end as mom_pcnt_change
from money_spine a 
join money_spine b
  on a.last_month_date = b.calendar_date


