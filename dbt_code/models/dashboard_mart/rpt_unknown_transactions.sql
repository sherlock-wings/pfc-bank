{{ config(location=data_path('dashboard_mart/rpt_unknown_transactions.parquet')) }}

select a.amount, a.posted_at_timestamp, a.payee, a.txn_description, b.merchant_category
from {{ ref('fact_transactions') }} a 
join {{ ref('dim_merchant') }} b
  on a.merchant_category_key = b.merchant_category_key
where b.merchant_category ilike '%unkn%'
-- When two transactions have different transaction IDs, but the same Account, 
-- description, payee, amount, and time of posting, assume they are NOT in fact 
-- two distinct transactions. Take whichever record was posted latest and call that
-- the *SOLE* transaction
qualify row_number() over (
        partition by a.bank_account_id
                    ,a.txn_description
                    ,a.payee
                    ,a.posted_at_timestamp
                    ,a.amount
        order     by a.record_loaded_at_timestamp             
) = 1