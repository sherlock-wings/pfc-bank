{{ config(materialized='external', format='parquet', location=data_path('stage/stg_payrate.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
--
-- Each persona has its own fictional employer, hence its own payrate. In persona
-- mode the seed is a CSV in S3 next to the persona's transactions; point at it with
--   --vars '{payrate_seed_csv: s3://pfc-nfcu/demo/<persona>/stage/seed_payrate.csv}'
-- With the var unset (the real pipeline) this reads the committed dbt seed exactly
-- as before, so the real seed is never touched.
{% if var('payrate_seed_csv', none) %}
  {% set payrate_source %}read_csv('{{ var('payrate_seed_csv') }}', header=true){% endset %}
{% else %}
  {% set payrate_source %}{{ ref('seed_payrate') }}{% endset %}
{% endif %}

select cast(employer_name as varchar)                     as employer_name
      ,cast(employer_address as varchar)                  as employer_address
      ,cast(biweekly_paycheck_posttax_amount as decimal(12,2)) as biweekly_paycheck_posttax_amount
      ,cast(effective_start_date as date)                 as effective_start_date
      ,cast(effective_end_date as date)                    as effective_end_date
from {{ payrate_source }}
