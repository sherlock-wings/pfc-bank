select 

year(posted_at_timestamp) || '|' || LPAD(CAST(EXTRACT(MONTH FROM posted_at_timestamp) AS VARCHAR), 2, '0')  as year_month, 
merchant_subcategory as subcategory,
sum(amount_spent) as amount_spent
from pfc_bank.rpt_expenses_detail
where amount_spent < 500.000
  and merchant_category = 'cost-of-living'
group by 1,2
order by year_month

