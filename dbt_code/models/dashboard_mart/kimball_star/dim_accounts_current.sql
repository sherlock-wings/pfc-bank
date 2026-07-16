{{ config(location=data_path('dashboard_mart/kimball_star/dim_accounts_current.parquet')) }}

select filename
      ,bank_account_id
      ,bank_account_name
      ,currency
      ,actual_balance
      ,available_balance
      ,balance_valid_from as balance_last_updated_timestamp
from {{ ref('dim_accounts') }} where is_current_ind = true