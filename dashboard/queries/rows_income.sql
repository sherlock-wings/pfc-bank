select date_trunc('day', posted_at_timestamp)::date as posted_date
      ,amount_earned
      ,txn_description as income_source 
from pfc_bank.rpt_income_detail
order by 1 desc