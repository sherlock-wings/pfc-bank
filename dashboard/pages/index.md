# {persona[0]?.family_name} Family Finances :)

```sql blnc_all_accounts
select sum(actual_balance) as balance, 'All' as account
from pfc_bank.dim_accounts_current
where bank_account_name not ilike '%mortgage%'
```
```sql blnc_main_savings
select sum(actual_balance) as balance, bank_account_name as account_name
from pfc_bank.dim_accounts_current
where bank_account_name ilike '%market savings%'
```
```sql blnc_alt_savings
select sum(actual_balance) as balance, bank_account_name as account_name
from pfc_bank.dim_accounts_current
where bank_account_name ilike '%share savings%'
```
```sql blnc_checking
select sum(actual_balance) as balance, bank_account_name as account_name
from pfc_bank.dim_accounts_current
where bank_account_name ilike '%check%'
```

<BigValue 
  data={blnc_all_accounts} 
  value=balance
  fmt=usd2
  title="Balance, All Accounts"
/>
<BigValue 
  data={blnc_main_savings} 
  value=balance
  title="Money Market Savings"
  fmt=usd2
/>
<BigValue 
  data={blnc_alt_savings} 
  value=balance
  title="Simple Savings"
  fmt=usd2
/>
<BigValue 
  data={blnc_checking} 
  value=balance
  title="Checking"
  fmt=usd2
/>