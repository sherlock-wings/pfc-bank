select posted_at_timestamp as posted_date, txn_description as description, account, amount_spent, merchant_category as category, merchant_subcategory as subcategory
from pfc_bank.rpt_expenses_detail
where amount_spent >= 500.000
  and description not ilike '%mortgage%'
  and date_trunc('month', posted_at_timestamp) 
  -- trailing 6 months
  between dateadd('month', -6, date_trunc('month', current_date()))
      and date_trunc('month', current_date())
order by posted_at_timestamp desc;