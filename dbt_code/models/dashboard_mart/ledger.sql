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

,anchor_cumsum as (
    -- initial_offset_balance is the true balance as of offset_as_of_date, which
    -- can land mid-history rather than before the first transaction. To anchor
    -- the running-balance series there, the flat offset added below has to net
    -- out whatever the transaction sum already accumulates by that date --
    -- otherwise every balance is off by the account's pre-anchor cumulative sum.
    select ib.account_name
          ,ib.initial_offset_balance
          ,coalesce(sum(d.txn_amount), 0) as cumsum_thru_anchor
    from {{ ref('stg_initial_balance') }} ib
    left join deduped d
           on d.account = ib.account_name
          and d.posted_at_timestamp::date <= ib.offset_as_of_date
    group by all
)

,blnc as (
select deduped.*
      ,try_cast(
          sum(txn_amount) over (partition by account
                                order     by posted_at_timestamp
                                            ,merchant_category
                                            ,merchant_subcategory
                                            ,merchant
                                            ,txn_description
                                            ,account
                                            ,txn_amount
                               ) + coalesce(ac.initial_offset_balance - ac.cumsum_thru_anchor, 0)
          as decimal(12,2)
       ) as acnt_running_balance
from deduped
left join anchor_cumsum ac
       on deduped.account = ac.account_name
)

select posted_at_timestamp
      ,merchant_category
      ,merchant_subcategory
      ,merchant
      ,txn_description
      ,account
      ,txn_amount
      ,last_value(acnt_running_balance ignore nulls) over (
              partition by account
              order     by posted_at_timestamp
                          ,merchant_category
                          ,merchant_subcategory
                          ,merchant
                          ,txn_description
                          ,account
                          ,txn_amount
              rows between unbounded preceding and current row
      ) as acnt_running_balance
from blnc
order by all