select date_trunc('day', posted_at_timestamp)::date as posted_date
      ,amount_spent
      ,merchant_category as category
      ,merchant_subcategory as subcategory
      ,merchant
      ,txn_description as description
      ,account
from pfc_bank.rpt_expenses_detail
where amount_spent >= 500.000 -- make this modular with 250, 500, 750, 1k+, etc filters
  and description not ilike '%mortgage%'
  and date_trunc('month', posted_at_timestamp) 
  -- trailing 6 months
  between date_trunc('month', current_date()) - interval 6 month
      and current_date()
order by posted_at_timestamp desc;