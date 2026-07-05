select sum(actual_balance) as total_balance from pfc_bank.dim_accounts
where bank_account_name ilike '%mortgage%';