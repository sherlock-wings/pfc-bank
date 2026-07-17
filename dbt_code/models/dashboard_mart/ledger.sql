{{ config(location=data_path('dashboard_mart/ledger.parquet')) }}

with deduped as (
    select f.posted_at_timestamp
          ,m.merchant_category
          ,m.merchant_subcategory
          ,f.payee as merchant
          ,f.txn_description
          ,f.bank_account_name as account
          ,try_cast(f.amount as decimal(12,2)) as txn_amount
    from {{ ref('fact_transactions') }} f
    left join {{ ref('dim_merchant')}} m
           on f.merchant_category_key = m.merchant_category_key
    qualify row_number() over (
            partition by f.bank_account_id
                        ,f.txn_description
                        ,f.payee
                        ,f.posted_at_timestamp
                        ,f.amount
            order     by f.record_loaded_at_timestamp desc nulls last
                        ,f.txn_id
    ) = 1
)

-- Bank-reported balance per account per reported date, straight from the account
-- SCD. This is the authoritative balance wherever the bank reported one. We
-- anchor the running balance to it rather than summing txns forward from a seed,
-- because the raw feed double-records some transactions (a verbose real-timestamp
-- version plus a terse restated one pinned to 08:00) that the dedup above can't
-- collapse -- so a pure txn sum drifts from the real balance. One row per
-- reported date (the SCD's daily grain), keeping the latest balance if a date
-- was synced more than once.
,reported as (
    select bank_account_name       as account
          ,balance_valid_from::date as valid_from_date
          ,actual_balance
    from {{ ref('dim_accounts') }}
    qualify row_number() over (
            partition by bank_account_name, balance_valid_from::date
            order     by balance_valid_from desc
    ) = 1
)

-- Earliest reported balance per account: the anchor we walk BACKWARD from to
-- cover pre-coverage history. Transactions predate the first reported balance
-- because each snapshot carries a long trailing txn window but only one
-- balance-date, so the reported-balance series is shorter than the txn history.
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
    from deduped
    group by all
)

-- Cumulative txn delta through each day, plus the cumulative delta as of the
-- anchor day (robust to the anchor day having no transactions of its own).
,day_cum as (
    select account
          ,posted_date
          ,day_total
          ,sum(day_total) over (partition by account order by posted_date) as cum_delta
    from day_delta
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

-- Attach each day's reported balance via an as-of join: the most recent
-- reported balance dated on or before that day (carries forward across any gap
-- days, and picks the latest value on SCD boundary days).
,day_reported as (
    select dc.account
          ,dc.posted_date
          ,dc.day_total
          ,dc.cum_delta
          ,r.actual_balance as reported_balance
    from day_cum dc
    asof left join reported r
      on dc.account = r.account
     and dc.posted_date >= r.valid_from_date
)

-- End-of-day balance D(day): reported balance if the bank gave us one for that
-- day, else walk back from the anchor via the pre-coverage txn deltas. The
-- pre-coverage walk can inherit feed noise, but there is no bank truth before
-- the anchor, so it's the best available -- and it never touches in-coverage
-- days, which take the reported balance verbatim.
,day_end as (
    select dr.account
          ,dr.posted_date
          ,dr.day_total
          ,coalesce(
              dr.reported_balance,
              a.anchor_balance + (dr.cum_delta - ac.anchor_cum_delta)
           ) as eod_balance
    from day_reported dr
    join anchor a      on dr.account = a.account
    join anchor_cum ac on dr.account = ac.account
)

-- Per-transaction running balance, pinned so the LAST txn of each day lands
-- exactly on that day's end-of-day balance. running = eod - (amount posted
-- later that day) = eod - day_total + running_sum_through_this_txn.
,blnc as (
    select d.*
          ,de.eod_balance
          ,de.day_total
          ,sum(d.txn_amount) over (
                partition by d.account, d.posted_at_timestamp::date
                order     by d.posted_at_timestamp
                            ,d.merchant_category
                            ,d.merchant_subcategory
                            ,d.merchant
                            ,d.txn_description
                            ,d.account
                            ,d.txn_amount
                rows between unbounded preceding and current row
           ) as run_incl_day
    from deduped d
    join day_end de
      on d.account = de.account
     and d.posted_at_timestamp::date = de.posted_date
)

select posted_at_timestamp
      ,merchant_category
      ,merchant_subcategory
      ,merchant
      ,txn_description
      ,account
      ,txn_amount
      ,try_cast(eod_balance - day_total + run_incl_day as decimal(12,2)) as acnt_running_balance
from blnc
order by all
