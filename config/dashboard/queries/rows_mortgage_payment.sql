select posted_at_timestamp as posted_date, txn_description as description, amount_spent, account
from pfc_bank.rpt_expenses_detail
where txn_description ilike '%mortgage%'