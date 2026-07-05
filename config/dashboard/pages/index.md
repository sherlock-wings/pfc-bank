---
title: Welcome to Evidence

queries:
  - total_accounts_balance: total_assets_minus_mortgage.sql
  - savings1_balance: total_savings1.sql
  - savings2_balance: total_savings2.sql
  - checking_balance: total_checking.sql
  - cc_debt: total_cc_debt.sql
  - mortgage: total_mortgage.sql
  - rows_mortgage: rows_mortgage_payment.sql
---
<BigValue 
  data={total_accounts_balance} 
  value=balance
  fmt=usd2
  title="Balance, All Accounts"
/>
<BigValue 
  data={savings1_balance} 
  value=balance
  title="Money Market Savings"
  fmt=usd2
/>
<BigValue 
  data={savings2_balance} 
  value=balance
  title="Simple Savings"
  fmt=usd2
/>
<BigValue 
  data={checking_balance} 
  value=balance
  title="Checking"
  fmt=usd2
/>

# Expenses

## Housing

<BigValue 
  data={mortgage} 
  value=balance
  title="Mortgage on 1047 Berry Patch Cir"
  fmt=usd2
/>

### Payments
<DataTable data={rows_mortgage}>
<Column id=posted_date/>
<Column id=description/>
<Column id=account/>
<Column id=amount_spent fmt=usd2/>
</DataTable>
