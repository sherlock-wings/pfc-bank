{{ config(materialized='external', format='parquet', location=data_path('stage/stg_payrate.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
select cast(employer_name as varchar)                     as employer_name
      ,cast(employer_address as varchar)                  as employer_address
      ,cast(biweekly_paycheck_posttax_amount as decimal(12,2)) as biweekly_paycheck_posttax_amount
      ,cast(effective_start_date as date)                 as effective_start_date
      ,cast(effective_end_date as date)                    as effective_end_date
from {{ ref('seed_payrate') }}
