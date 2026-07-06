select category
      ,subcategory
      ,sum(total_spend) as total_spend
from pfc_bank.rpt_top_expenses
group by 1,2 order by all