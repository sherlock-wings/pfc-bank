{{ config(materialized='external', format='parquet', location=data_path('stage/stg_initial_balance.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
--
-- The real account balance as of the day data collection started cannot be
-- committed to this public repo, so it is read from S3 via
-- initial_balance_seed_csv, which dbt_project.yml defaults to
-- s3://pfc-nfcu/config/seed_initial_balance.csv.
--
-- The committed seed is a zero-balance placeholder used only if the var is
-- explicitly cleared. Zero is on purpose: a running balance visibly collapses
-- to the raw transaction sum rather than quietly offsetting by a
-- plausible-looking fake balance.
{% if var('initial_balance_seed_csv', none) %}
  {% set initial_balance_source %}read_csv('{{ var('initial_balance_seed_csv') }}', header=true){% endset %}
{% else %}
  {% set initial_balance_source %}{{ ref('seed_initial_balance') }}{% endset %}
{% endif %}

select cast(balance_as_of_timestamp as timestamptz) as balance_as_of_timestamp
      ,cast(account_balance as decimal(12,2))       as account_balance
from {{ initial_balance_source }}
