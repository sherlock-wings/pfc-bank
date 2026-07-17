{{ config(location=data_path('dashboard_mart/daily_tally.parquet')) }}

-- Bank-reported balance per account per reported date (SCD's daily grain), one
-- row per date keeping the latest balance if a date was synced more than once.
with reported as (
    select bank_account_name       as account
          ,balance_valid_from::date as valid_from_date
          ,actual_balance
    from {{ ref('dim_accounts') }}
    qualify row_number() over (
            partition by bank_account_name, balance_valid_from::date
            order     by balance_valid_from desc
    ) = 1
)

-- Earliest reported balance = the backward anchor for pre-coverage history.
,anchor as (
    select account
          ,actual_balance  as anchor_balance
          ,valid_from_date as anchor_date
    from reported
    qualify row_number() over (partition by account order by valid_from_date) = 1
)

,day_delta as (
    select account
          ,posted_at_timestamp::date as posted_date
          ,sum(txn_amount)           as day_total
          ,count(*)                  as eod_txn_count
    from {{ ref('ledger') }}
    group by all
)

,anchor_cum as (
    select a.account
          ,coalesce(sum(dd.day_total), 0) as anchor_cum_delta
    from anchor a
    left join day_delta dd
           on dd.account = a.account
          and dd.posted_date <= a.anchor_date
    group by a.account
)

-- One row per account per calendar day from first activity through today, so a
-- balance exists every day (no gaps) and the month-over-month self-join below
-- always finds the same-day-last-month row.
,spine as (
    select acct.account
          ,d.full_date as posted_date
    from {{ ref('dim_date') }} d
    cross join (select distinct account from day_delta) acct
    where d.full_date between (select min(posted_date) from day_delta)
                          and current_date
)

,spine_delta as (
    select s.account
          ,s.posted_date
          ,s.posted_date - interval 1 month as last_month_date
          ,coalesce(dd.eod_txn_count, 0) as eod_txn_count
          ,sum(coalesce(dd.day_total, 0)) over (
                partition by s.account order by s.posted_date
           ) as cum_delta
    from spine s
    left join day_delta dd
           on s.account = dd.account and s.posted_date = dd.posted_date
)

-- Attach each day's reported balance via an as-of join: the most recent reported
-- balance dated on or before that day (carries forward across gap days and picks
-- the latest value on SCD boundary days).
,daily as (
    select sd.*
          ,r.actual_balance as reported_balance
    from spine_delta sd
    asof left join reported r
      on sd.account = r.account
     and sd.posted_date >= r.valid_from_date
)

-- End-of-day balance: reported where the bank gave us one, else the backward
-- walk from the anchor. See ledger.sql for why we trust the reported balance
-- over a forward txn sum (double-counted restatements in the raw feed).
,blnc as (
    select d.account
          ,d.posted_date
          ,d.last_month_date
          ,d.eod_txn_count
          ,coalesce(
              d.reported_balance,
              a.anchor_balance + (d.cum_delta - ac.anchor_cum_delta)
           ) as acnt_balance
    from daily d
    join anchor a      on d.account = a.account
    join anchor_cum ac on d.account = ac.account
)

select a.account
      ,a.posted_date
      ,a.eod_txn_count
      ,try_cast(a.acnt_balance as decimal(12,2)) as acnt_balance
      ,try_cast(b.acnt_balance as decimal(12,2)) as last_month_balance
      ,try_cast(a.acnt_balance - b.acnt_balance as decimal(12,2)) as mom_dollars_change
      ,case
            when b.acnt_balance <> 0
            then try_cast(round((a.acnt_balance - b.acnt_balance)/abs(b.acnt_balance),4) as decimal(14,4))
       end as mom_pcnt_change
from blnc a
left join blnc b
  on a.last_month_date = b.posted_date
 and a.account = b.account
order by all
