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
    -- Transfers between checkings and savings accounts are not
    -- expenses, nor income. Filter out net-zero txns
    where (
        (f.txn_description ilike '%transfer%' and f.txn_description ilike '%credit card%')
        or
        (f.txn_description ilike '%transfer%' and f.txn_description ilike '%mortgage%')
        or
        f.txn_description not ilike '%transfer%'
      )
    -- When two transactions have different transaction IDs, but the same Account, 
    -- description, payee, amount, and time of posting, assume they are NOT in fact 
    -- two distinct transactions. Take whichever record was posted latest and call that
    -- the *SOLE* transaction
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
                               ) --+ ib.account_balance
          as decimal(12,2)
       ) as acnt_running_balance
from deduped
cross join {{ ref('stg_initial_balance') }} ib
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