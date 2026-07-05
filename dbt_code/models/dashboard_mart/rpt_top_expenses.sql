{{ config(location='s3://pfc-nfcu/dashboard_mart/rpt_top_expenses.parquet') }}
select merchant_name
      ,merchant_category
      ,merchant_subcategory
      ,earliest_txn_at
      ,latest_txn_at
      ,total_transactions
      ,total_amount*-1 as total_spend
      ,try_cast(round(total_transactions/total_amount*-1 ,2) as decimal(38,2)) as avg_spend_per_txn
from {{ ref('dim_merchant') }}
where merchant_category not like '%transfer%'
  and total_amount < 0 
order by total_amount*-1 desc