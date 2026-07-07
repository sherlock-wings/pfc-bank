{{ config(location='s3://pfc-nfcu/dashboard_mart/rpt_top_expenses.parquet') }}
select merchant_name
      ,merchant_category as category
      ,merchant_subcategory as subcategory
      ,total_amount*-1 as total_spend
      ,amount_past_day*-1 as past_day
      ,amount_past_week*-1 as past_week
      ,amount_past_month*-1 as past_month
      ,amount_past_quarter*-1 as past_quarter
      ,amount_past_year*-1 as past_year
      ,earliest_txn_at
      ,latest_txn_at
      ,total_transactions
      ,try_cast(round(total_transactions/total_amount*-1 ,2) as decimal(38,2)) as avg_spend_per_txn
from {{ ref('dim_merchant') }}
where total_amount < 0 
-- transfers to the Credit Card or to the Mortage are expenses
-- transfers between checkings and savings accounts are not
  and (
    (txn_description ilike '%transfer%' and txn_description ilike '%credit card%')
    or
    (txn_description ilike '%transfer%' and txn_description ilike '%mortgage%')
    or
    txn_description not ilike '%transfer%'
  ) 
order by total_amount*-1 desc