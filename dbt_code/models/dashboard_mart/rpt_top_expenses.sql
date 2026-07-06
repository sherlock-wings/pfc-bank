{{ config(location='s3://pfc-nfcu/dashboard_mart/rpt_top_expenses.parquet') }}
select merchant_name
      ,merchant_category as category
      ,merchant_subcategory as subcategory
      ,earliest_txn_at
      ,latest_txn_at
      ,total_transactions
      ,try_cast(round(total_transactions/total_amount*-1 ,2) as decimal(38,2)) as avg_spend_per_txn
      ,total_amount*-1 as total_spend
      ,amount_past_day*-1 as past_day
      ,amount_past_week*-1 as past_week
      ,amount_past_month*-1 as past_month
      ,amount_past_quarter*-1 as past_quarter
      ,amount_past_year*-1 as past_year
from {{ ref('dim_merchant') }}
where merchant_category not like '%transfer%'
  and total_amount < 0 
  and merchant_subcategory not ilike '%kratom%'
order by total_amount*-1 desc