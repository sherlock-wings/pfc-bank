{{ config(materialized='external', format='parquet', location=data_path('stage/stg_payrate.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
--
-- A payrate names a real employer, address and salary, so it cannot be committed
-- to this public repo. The real one is read from S3 via payrate_seed_csv, which
-- dbt_project.yml defaults to s3://pfc-nfcu/config/seed_payrate.csv. Personas
-- override it with their own fictional employer (see run-demo.sh).
--
-- The committed seed is a zero-income placeholder used only if the var is
-- explicitly cleared. Zero is on purpose: daily income visibly collapses to 0
-- rather than quietly computing off a plausible-looking fake rate.
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
