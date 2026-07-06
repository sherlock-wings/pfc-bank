select date_trunc('day', posted_at_timestamp)::date as posted_date
      ,amount_spent
      ,merchant
      ,merchant_category as category
      ,merchant_subcategory as subcategory
      ,txn_description as description
from pfc_bank.rpt_expenses_detail
where merchant_category || merchant_subcategory not ilike '%kratom%'
  and date_trunc('month', posted_at_timestamp) 
  -- trailing 6 months
  between date_trunc('month', current_date()) - interval 6 month
      and date_trunc('month', current_date())
order by 1 desc