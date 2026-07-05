select posted_at_timestamp as posted_date, amount_spent, merchant_category as category, merchant_subcategory as subcategory, merchant, txn_description as description, account
from pfc_bank.rpt_expenses_detail
where account ilike '%cashreward%'
  and txn_description ilike '%interest%'
order by posted_at_timestamp desc