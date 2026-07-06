select
strftime(date_trunc('month', posted_at_timestamp), '%Y-%m') as year_month,
merchant_subcategory as subcategory,
sum(amount_spent) as amount_spent
from pfc_bank.rpt_expenses_detail
where amount_spent < 500.000
  and merchant_category = 'cost-of-living'
  and date_trunc('month', posted_at_timestamp) 
  -- trailing 6 months
  between dateadd('month', -6, date_trunc('month', current_date()))
      and date_trunc('month', current_date())
group by 1,2
order by year_month

