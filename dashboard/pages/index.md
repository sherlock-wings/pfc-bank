---
queries:
  - persona: persona_info.sql
  - total_accounts_balance: total_assets_minus_mortgage.sql
  - savings1_balance: total_savings1.sql
  - savings2_balance: total_savings2.sql
  - checking_balance: total_checking.sql
  - cc_debt: total_cc_debt.sql
  - mortgage: total_mortgage.sql
  - rows_mortgage: rows_mortgage_payment.sql
  - rows_interest: rows_cc_interest_payments.sql
  - chart_coe_expenses: chart_coe_expenses_detail.sql
  - rows_all_expenses: rows_all_expenses.sql
  - rows_all_income: rows_income.sql
  - chart_monthly_savings: chart_monthly_savings.sql
---

# {persona[0]?.family_name} Family Finances :)

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
  title="Mortgage on {persona[0]?.home_address}"
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

```sql rows_cc_spend 
select * from ${rows_all_expenses}
where account ilike '%cashreward%'
order by posted_date desc
```

<BigValue 
  data={cc_debt} 
  value=balance
  title="Current Credit Card Balance"
  fmt=usd2
/>

### Spend on Purchases
<DataTable data={rows_cc_spend} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=category/>
<Column id=subcategory/>
<Column id=merchant/>
<Column id=description/>
</DataTable>

### Spend on Interest
<DataTable data={rows_interest} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=category/>
<Column id=subcategory/>
<Column id=merchant/>
<Column id=description/>
</DataTable>

## Cost of Living 

<BarChart 
    data={chart_coe_expenses}
    x=year_month
    y=amount_spent 
    yAxisTitle="Total Expense ($)"
    series=subcategory
    xGridLines=false
    sort=false
    legend=false
/>

## All Expenses

### By Category

```sql col_dollar_bounds
select min(amount_spent) as least_spent, max(amount_spent) as most_spent
from ${rows_all_expenses}
```

```sql flt_chart_col_expenses
select category
      ,subcategory
      ,sum(amount_spent) as total_spend
from ${rows_all_expenses}
where amount_spent <= coalesce(try_cast('${inputs.COL_dollar_filter}' as decimal(36,2)), 999999999999.99)
group by 1,2 order by all
```
Filter by Purchases under Dollar Amount

<TextInput
    name=COL_dollar_filter
    placeholder="Enter Dollar Amount"
    defaultValue="9999999999999"
/>


<BarChart 
    data={flt_chart_col_expenses}
    x=category
    y=total_spend 
    yAxisTitle="Total Expense ($)"
    series=subcategory
    xGridLines=false
    sort=true
    legend=false
    type=stacked
    swapXY=true
    echartsOptions={{
        tooltip: {
            formatter: (params) => {
                const rows = params
                    .filter((p) => p.seriesName !== 'stackTotal' && p.value[0])
                    .sort((a, b) => b.value[0] - a.value[0]);
                if (!rows.length) return '';
                let output = `<span id="tooltip" style='font-weight: 600;'>${params[0].name}</span>`;
                for (const p of rows) {
                    output += `<br><span style='font-size: 11px;'>${p.marker} ${p.seriesName}</span><span style='float:right; margin-left: 10px; font-size: 12px;'>${p.value[0].toLocaleString(undefined, { maximumFractionDigits: 2 })}</span>`;
                }
                return output;
            }
        }
    }}
/>

### By Line-Item

```sql unique_merch_cats
select distinct category from ${rows_all_expenses}
order by category
```

```sql expenses_detail_bounds 
select min(posted_at_timestamp) as start_date,
       date_diff('day', min(posted_at_timestamp), max(posted_at_timestamp)) as date_span
from pfc_bank.rpt_expenses_detail
```

```sql flt_rows_all_expenses 
select *
from ${rows_all_expenses}
where posted_date between 
coalesce(try_cast('${inputs.exp_lower_bound}' as date), '1900-01-01'::date)
and 
coalesce(try_cast('${inputs.exp_upper_bound}' as date), '9999-12-31'::date)
and category in  ${inputs.merch_cat_select.value}
```

```sql expenses_cutoff_date 
select (
    select min(posted_at_timestamp) + interval ${inputs.expensesDateSlider} day
    from pfc_bank.rpt_expenses_detail
)::date as expenses_as_of
```

<Dropdown 
    data={unique_merch_cats} 
    title="Filter by category"
    name=merch_cat_select 
    value=category
    multiple
    defaultValue="cost-of-living"
/>

<TextInput
    name=exp_lower_bound
    placeholder="Enter Start Date (YYYY-MM-DD)"
    defaultValue="1900-01-01"
/>
<TextInput
    name=exp_upper_bound
    placeholder="Enter End Date (YYYY-MM-DD)"
    defaultValue="9999-12-31"
/>

<DataTable data={flt_rows_all_expenses} totalRow=true>
<Column id=posted_date/>
<Column id=amount_spent fmt=usd2/>
<Column id=description/>
<Column id=category/>
<Column id=subcategory/>
</DataTable>


# Income

```sql savings_bounds 
select min(year_month) as start_month,
       date_diff('month', min(year_month), max(year_month)) as month_span
from pfc_bank.rpt_monthly_savings
```

```sql total_saved 
select sum(dollars_saved) as savings
from pfc_bank.rpt_monthly_savings
where year_month <= (
    select min(year_month) + to_months(${inputs.savingsMonthSlider}::integer)
    from pfc_bank.rpt_monthly_savings
)
```

```sql savings_cutoff_month 
select (
    select min(year_month) + to_months(${inputs.savingsMonthSlider}::integer)
    from pfc_bank.rpt_monthly_savings
)::date as savings_as_of
```

👇Cumulative savings from **<Value data={savings_bounds} column=start_month fmt="mmmm yyyy" />** through **<Value data={savings_cutoff_month} column=savings_as_of fmt="mmmm yyyy" />**

<BigValue 
  data={total_saved} 
  value=savings
  fmt=usd2
  title="Total Saved"
/>

<Slider
    title='Filter by Month'
    name='savingsMonthSlider'
    size=large
    data={savings_bounds}
    min=0
    maxColumn=month_span
    defaultValue=month_span
    step=1
/>



## Savings, by Month

<BarChart 
    data={chart_monthly_savings} 
    x=year_month 
    y=total_spend 
    y2=total_earned
    sort=false
    echartsOptions={{
        tooltip: {
            formatter: (params) => {
                const row = chart_monthly_savings[params[0].dataIndex];
                if (!row) return '';
                const pct = (v) => (v * 100).toFixed(1) + '%';
                const usd = (v) => v.toLocaleString(undefined, { style: 'currency', currency: 'USD' });
                let output = `<span style='font-weight:600;'>${params[0].value[0]}</span>`;
                for (const p of params) {
                    output += `<br/>${p.marker} ${p.seriesName}: ${usd(p.value[1])}`;
                }
                output += `<br/>Saved: ${usd(row.dollars_saved)} (${pct(row.pcnt_saved)})`;
                output += `<br/>Lost: ${usd(row.dollars_lost)} (${pct(row.pcnt_lost)})`;
                return output;
            }
        }
    }}
/>

## All Income streams

```sql unique_inc_types 
select distinct income_type from ${rows_all_income}
```
```sql flt_rows_all_income
select * from ${rows_all_income}
where income_type in ${inputs.inc_type_select.value}
```
<Dropdown 
    data={unique_inc_types} 
    title="Filter by Income Type"
    name=inc_type_select 
    value=income_type
    multiple
    defaultValue="payments | paycheck"
/>

<DataTable data={flt_rows_all_income} totalRow=true>
<Column id=posted_date/>
<Column id=amount_earned fmt=usd2/>
<Column id=income_type/>
<Column id=income_source/>
</DataTable>
