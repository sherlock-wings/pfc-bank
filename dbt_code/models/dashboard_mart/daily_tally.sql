{{ config(location=data_path('dashboard_mart/daily_tally.parquet')) }} 

with money_spine as (
    select account
          ,posted_at_timestamp::date as posted_date
          ,posted_at_timestamp::date - interval 1 month as last_month_date
          ,count(case when txn_amount is not null then 1 end) as eod_txn_count 
          ,coalesce(sum(txn_amount),0) as eod_balance
    from {{ ref('ledger')}}
    group by all 
)

select a.account
      ,a.posted_date
      ,try_cast(a.eod_balance as decimal(12,2)) as eod_balance
      ,try_cast(b.eod_balance as decimal(12,2)) as last_month_eod_balance
      ,try_cast(b.eod_balance - a.eod_balance as decimal(12,2)) as mom_dollars_change
      ,case 
            when b.eod_balance <> 0
            then try_cast(round((a.eod_balance - b.eod_balance)/abs(b.eod_balance),4) as decimal (14,4))
      end as mom_pcnt_change
from money_spine a 
join money_spine b
  on a.last_month_date = b.posted_date
 and a.account = b.account



