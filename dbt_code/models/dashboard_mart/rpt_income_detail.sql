{{ config(location=data_path('dashboard_mart/rpt_income_detail.parquet')) }}

select f.posted_at_timestamp
      ,m.merchant_category
      ,m.merchant_subcategory
      ,f.payee as merchant
      ,f.txn_description
      ,f.bank_account_name as account
      ,f.amount as amount_earned
from {{ ref('fact_transactions') }} f
left join {{ ref('dim_merchant') }} m
       on f.merchant_category_key = m.merchant_category_key
where m.merchant_category not ilike '%transfer%'
  and f.amount >= 0
order by all