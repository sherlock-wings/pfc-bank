{{ config(location=data_path('dashboard_mart/kimball_star/dim_accounts.parquet')) }}

with init as (
      select unnest(accounts) as acnt
            ,filename
      from read_json_auto({{ source('nfcu_raw', 'transactions')}})
)

,dedupe as (
      select filename
            ,acnt.id as bank_account_id
            ,acnt.name as bank_account_name
            ,acnt.currency
            ,try_cast(acnt.balance as decimal(14,2)) as actual_balance
            ,try_cast(acnt."available-balance" as decimal(14,2)) as available_balance
            ,to_timestamp(acnt."balance-date") as balance_valid_from
      from init
      qualify row_number() over (
            partition by bank_account_id, balance_valid_from
            order     by actual_balance desc
      ) = 1
)

,lead_tbl as (
      select *
            ,lead(balance_valid_from) over (
                  partition by bank_account_id
                  order by balance_valid_from
            ) as balance_valid_to
      from dedupe 
)

select md5(coalesce(bank_account_id:: varchar, 'NULL')
           || '||' ||
           coalesce(balance_valid_from:: varchar, 'NULL')
          ) as account_scd_key
      ,* exclude(balance_valid_to)
      ,case 
         when balance_valid_to is not null
         then balance_valid_to - interval 1 second
         when balance_valid_to is null
         then strptime('9999-12-31 23:59:59', '%Y-%m-%d %H:%M:%S')
       end as balance_valid_to
      ,case 
         when balance_valid_to is not null
         then false
         else true
       end as is_current_ind
      ,get_current_timestamp() as record_loaded_at_timestamp
from lead_tbl
order by bank_account_id, balance_valid_from
