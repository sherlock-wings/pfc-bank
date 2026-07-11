{{ config(location=data_path('dashboard_mart/rpt_expenses_detail.parquet')) }}

select f.posted_at_timestamp
      ,m.merchant_category
      ,m.merchant_subcategory
      ,f.payee as merchant
      ,f.txn_description
      ,f.bank_account_name as account
      ,f.amount*-1 as amount_spent
from {{ ref('fact_transactions') }} f
left join {{ ref('dim_merchant')}} m
       on f.merchant_category_key = m.merchant_category_key
where total_amount < 0 
-- transfers to the Credit Card or to the Mortage are expenses
-- transfers between checkings and savings accounts are not
  and (
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
        order     by f.record_loaded_at_timestamp             
) = 1
order by all