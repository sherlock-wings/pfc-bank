with init as (
select unnest(accounts) as acnt
      ,filename
from read_json_auto({{ source('nfcu_raw', 'transactions')}})
)

select acnt.id as bank_account_id
      ,acnt.name as bank_account_name
      ,acnt.currency
      ,acnt.balance as actual_balance
      ,acnt."available-balance" as available_balance
      ,to_timestamp(acnt."balance-date") as balance_as_of_timestamp
      ,filename
      ,get_current_timestamp() as record_loaded_at_timestamp
from init
qualify row_number() over (
        partition by bank_account_id
        order     by balance_as_of_date desc
) = 1