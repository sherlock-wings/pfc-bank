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

-- Trust floor: each account's earliest bank-reported date. We only ever serve
-- balances at or after this date. Before it there is no bank balance to anchor
-- to (SimpleFIN doesn't retain/backfill older snapshots) and the raw feed has
-- known-unverifiable stretches (e.g. the 2026-05-31 batch that isn't on the
-- statement), so a reconstructed pre-anchor balance can't be trusted -- and an
-- untrustworthy balance would silently poison the month-over-month comparison.
,anchor as (
    select account
          ,min(valid_from_date) as anchor_date
    from reported
    group by account
)

,day_delta as (
    select account
          ,posted_at_timestamp::date as posted_date
          ,count(*)                  as eod_txn_count
    from {{ ref('ledger') }}
    group by all
)

-- One row per account per calendar day from the account's anchor date through
-- today (no gaps), so a balance exists every day and the month-over-month
-- self-join always finds the same-day-last-month row when it is in range.
,spine as (
    select a.account
          ,d.full_date as posted_date
    from {{ ref('dim_date') }} d
    join anchor a
      on d.full_date between a.anchor_date and current_date
)

,spine_delta as (
    select s.account
          ,s.posted_date
          ,s.posted_date - interval 1 month as last_month_date
          ,coalesce(dd.eod_txn_count, 0)     as eod_txn_count
    from spine s
    left join day_delta dd
           on s.account = dd.account and s.posted_date = dd.posted_date
)

-- Attach each day's reported balance via an as-of join: the most recent reported
-- balance dated on or before that day (carries forward across gap days and today,
-- and picks the latest value on SCD boundary days). Because the spine starts at
-- the anchor date, every served day has a reported balance -- acnt_balance is
-- always the bank's own number, never a reconstruction.
,blnc as (
    select sd.account
          ,sd.posted_date
          ,sd.last_month_date
          ,sd.eod_txn_count
          ,r.actual_balance as acnt_balance
    from spine_delta sd
    asof left join reported r
      on sd.account = r.account
     and sd.posted_date >= r.valid_from_date
)

-- Month-over-month vs the same calendar day one month prior. The self-join only
-- finds a row when last_month_date is itself at/after the anchor (it's on the
-- floored spine), so for roughly the first month of coverage last_month_balance
-- is null and the MoM columns stay null -- the dashboard shows "building history"
-- rather than a comparison against an untrusted pre-anchor balance.
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
