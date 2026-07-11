{{ config(location=data_path('dashboard_mart/rpt_unknown_transactions.parquet')) }}

select a.amount, a.posted_at_timestamp, a.payee, a.txn_description, b.merchant_category
from {{ ref('fact_transactions') }} a 
join {{ ref('dim_merchant') }} b
  on a.merchant_category_key = b.merchant_category_key
where b.merchant_category ilike '%unkn%'
