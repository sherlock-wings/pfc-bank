{{ config(materialized='external', format='parquet', location=data_path('stage/map_merchant_category_regex.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
--
-- The merchant catalog is committed (it names no one), but the paycheck row is
-- not: it matches on a real employer/payroll-processor string, so it lives only
-- in S3 and is unioned on here. Two independent knobs:
--
--   regex_seed_csv    REPLACES the whole catalog. Persona mode only -- a persona's
--                     merchants are wholly different, not an addition to yours.
--                     run-demo.sh passes it (see run-demo.sh).
--   regex_overlay_csv ADDS rows to the catalog. Defaulted in dbt_project.yml to
--                     the real paycheck row in s3://pfc-nfcu/config/.
--
-- Setting regex_seed_csv suppresses the overlay: a persona build must never emit
-- the real employer into the public demo site, so replacement implies no overlay
-- rather than trusting every caller to unset the overlay by hand.
--
-- If the overlay is missing, paychecks fall through to '**UNKNOWN**' and surface
-- in rpt_unknown_transactions. That is deliberate -- a visibly wrong category
-- beats silently reclassifying real income.
{% if var('regex_seed_csv', none) %}
  {% set regex_source %}read_csv('{{ var('regex_seed_csv') }}', header=true){% endset %}
  {% set regex_overlay = none %}
{% else %}
  {% set regex_source %}{{ ref('seed_merchant_category_regex_mapping') }}{% endset %}
  {% set regex_overlay = var('regex_overlay_csv', none) %}
{% endif %}
select cast(merchant_category as varchar)    as merchant_category
      ,cast(merchant_subcategory as varchar) as merchant_subcategory
      ,cast(regex_match_pat as varchar)      as regex_match_pat
      ,cast(match_priority as integer)       as match_priority
from {{ regex_source }}

{% if regex_overlay %}
union all

select cast(merchant_category as varchar)    as merchant_category
      ,cast(merchant_subcategory as varchar) as merchant_subcategory
      ,cast(regex_match_pat as varchar)      as regex_match_pat
      ,cast(match_priority as integer)       as match_priority
from read_csv('{{ regex_overlay }}', header=true)
{% endif %}
