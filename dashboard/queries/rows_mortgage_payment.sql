select date_trunc('day', posted_at_timestamp)::date as posted_date
      ,txn_description as description
      ,amount_spent
      ,account
from pfc_bank.rpt_expenses_detail
where txn_description ilike '%mortgage%'
  and date_trunc('month', posted_at_timestamp) 
  -- trailing 6 months
  between date_trunc('month', current_date()) - interval 6 month
      and date_trunc('month', current_date())
order by posted_at_timestamp desc