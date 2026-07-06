select year(year_month)::varchar || '|' || lpad(month(year_month)::varchar, 2, '0') as year_month
      ,total_spend
      ,total_earned
      ,dollars_saved
      ,pcnt_saved
      ,dollars_lost
      ,pcnt_lost
from pfc_bank.rpt_monthly_savings
order by 1