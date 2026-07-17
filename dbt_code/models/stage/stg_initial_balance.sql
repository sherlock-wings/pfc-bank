{{ config(materialized='external', format='parquet', location=data_path('stage/stg_initial_balance.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
--
-- The real per-account balances cannot be committed to this public repo, so
-- they are read from S3 via initial_balance_seed_csv, which dbt_project.yml
-- defaults to s3://pfc-nfcu/config/seed_initial_balance.csv.
--
-- Each row is a calibration point, not a starting balance: initial_offset_balance
-- is the true NFCU-reported balance for that account as of offset_as_of_date
-- (typically the account's most recently synced day). ledger.sql adds it as a
-- flat constant across the whole account's partition, so it's a constant shift
-- of the entire running-balance series -- it doesn't matter that the anchor
-- lands at the newest transaction rather than the oldest.
--
-- The committed seed is an empty placeholder (header only) used only if the
-- var is explicitly cleared. Empty is on purpose: ledger.sql left-joins on
-- account_name and coalesces missing offsets to 0, so a running balance
-- visibly collapses to the raw transaction sum rather than quietly
-- offsetting by a plausible-looking fake balance.
{% if var('initial_balance_seed_csv', none) %}
  {% set initial_balance_source %}read_csv('{{ var('initial_balance_seed_csv') }}', header=true){% endset %}
{% else %}
  {% set initial_balance_source %}{{ ref('seed_initial_balance') }}{% endset %}
{% endif %}

select cast(offset_as_of_date as date)              as offset_as_of_date
      ,cast(account_name as text)                   as account_name
      ,cast(initial_offset_balance as decimal(12,2)) as initial_offset_balance
from {{ initial_balance_source }}
