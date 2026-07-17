{{ config(location=data_path('dashboard_mart/rpt_transaction_daily.parquet')) }} 

with money_spine as (
    select 'ALL' as account
          ,calendar_date
          ,calendar_date - interval 1 month as last_month_date
          ,count(case when txn_amount is not null then 1 end) as eod_txn_count 
          ,coalesce(sum(txn_amount),0) as eod_balance
    from {{ ref('rpt_transaction_detail')}}
    group by all 
)

,all_diff as (
    select a.account
          ,a.calendar_date
          ,try_cast(a.eod_balance as decimal(12,2)) as eod_balance
          ,try_cast(b.eod_balance as decimal(12,2)) as last_month_eod_balance
          ,try_cast(b.eod_balance - a.eod_balance as decimal(12,2)) as mom_dollars_change
          ,case 
             when b.eod_balance <> 0
             then try_cast(round((a.eod_balance - b.eod_balance)/abs(b.eod_balance),4) as decimal (14,4))
           end as mom_pcnt_change
    from money_spine a 
    join money_spine b
      on a.last_month_date = b.calendar_date
)

,acnt_money_spine as (
    select calendar_date
          ,calendar_date - interval 1 month as last_month_date
          ,account
          ,count(case when txn_amount is not null then 1 end) as eod_txn_count 
          ,coalesce(sum(txn_amount),0) as eod_balance
    from {{ ref('rpt_transaction_detail')}}
    group by all 
)


,acnt_diff as (
    select a.account
          ,a.calendar_date
          ,try_cast(a.eod_balance as decimal(12,2)) as eod_balance
          ,try_cast(b.eod_balance as decimal(12,2)) as last_month_eod_balance
          ,try_cast(b.eod_balance - a.eod_balance as decimal(12,2)) as mom_dollars_change
          ,case 
             when b.eod_balance <> 0
             then try_cast(round((a.eod_balance - b.eod_balance)/abs(b.eod_balance),4) as decimal (14,4))
           end as mom_pcnt_change
    from acnt_money_spine a 
    join acnt_money_spine b
      on a.last_month_date = b.calendar_date
     and a.account = b.account
)

,final as (
select * from all_diff
union all
select * from acnt_diff
)

select * from final order by all


