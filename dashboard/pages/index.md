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
  - rows_interest: rows_cc_interest_payments.sql
  - rows_coe_expenses: rows_coe_expenses_detail.sql
  - rows_big_expenses: rows_big_ticket.sql
  - rows_all_expenses: rows_all_expenses.sql
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

<DataTable data={rows_mortgage} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=description/>
<Column id=account/>
</DataTable>

## Credit Card Debt

<BigValue 
  data={cc_debt} 
  value=balance
  title="Credit Card Debt"
  fmt=usd2
/>

<DataTable data={rows_interest} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=category/>
<Column id=subcategory/>
<Column id=merchant/>
<Column id=description/>
</DataTable>

## Large One-time Expenses
<DataTable data={rows_big_expenses} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=description/>
<Column id=account/>
</DataTable>

## Cost of Living 

<BarChart 
    data={rows_coe_expenses}
    x=year_month
    y=amount_spent 
    yAxisTitle="Total Expense ($)"
    series=subcategory
/>

## All Expenses

<DataTable data={rows_all_expenses} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=description/>
<Column id=category/>
<Column id=subcategory/>
</DataTable>

