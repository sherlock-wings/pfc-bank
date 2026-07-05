select posted_at_timestamp as posted_date
      ,amount_spent
      ,merchant
      ,merchant_category as category
      ,merchant_subcategory as subcategory
      ,txn_description as description
from pfc_bank.rpt_expenses_detail
where merchant_category || merchant_subcategory not ilike '%kratom%'
order by 1 desc