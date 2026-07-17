{{ config(location=data_path('dashboard_mart/daily_tally.parquet')) }} 

with day_end as (
    -- ledger already carries the correctly-offset running balance per txn;
    -- re-deriving it here from raw deltas + initial_offset_balance risks
    -- drifting out of sync with that calculation, so just read it back.
    select account
          ,posted_at_timestamp::date as posted_date
          ,txn_amount
          ,last_value(acnt_running_balance) over (
                partition by account
                            ,posted_at_timestamp::date
                order     by posted_at_timestamp
                            ,merchant_category
                            ,merchant_subcategory
                            ,merchant
                            ,txn_description
                            ,account
                            ,txn_amount
                rows between unbounded preceding and unbounded following
          ) as acnt_balance
    from {{ ref('ledger') }}
)

,money_spine as (
    select account
          ,posted_date
          ,posted_date - interval 1 month as last_month_date
          ,count(case when txn_amount is not null then 1 end) as eod_txn_count
          ,max(acnt_balance) as acnt_balance
    from day_end
    group by all
)

select a.account
      ,a.posted_date
      ,try_cast(a.acnt_balance as decimal(12,2)) as acnt_balance
      ,try_cast(b.acnt_balance as decimal(12,2)) as last_month_balance
      ,try_cast(b.acnt_balance - a.acnt_balance as decimal(12,2)) as mom_dollars_change
      ,case
            when b.acnt_balance <> 0
            then try_cast(round((a.acnt_balance - b.acnt_balance)/abs(b.acnt_balance),4) as decimal (14,4))
      end as mom_pcnt_change
from money_spine a
join money_spine b
  on a.last_month_date = b.posted_date
 and a.account = b.account



