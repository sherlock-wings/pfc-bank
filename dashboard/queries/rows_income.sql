select date_trunc('day', posted_at_timestamp)::date as posted_date
      ,amount_earned
      ,txn_description as income_source 
from pfc_bank.rpt_income_detail 
where date_trunc('month', posted_at_timestamp)
  -- trailing 6 months
  between date_trunc('month', current_date()) - interval 6 month
      and current_date()
order by 1 desc