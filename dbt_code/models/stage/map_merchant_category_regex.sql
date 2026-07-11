{{ config(materialized='external', format='parquet', location=data_path('stage/map_merchant_category_regex.parquet')) }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
--
-- Each persona has its own merchant catalog, hence its own regex map. In persona
-- mode the map is a CSV in S3 next to the persona's transactions; point at it with
--   --vars '{regex_seed_csv: s3://pfc-nfcu/demo/<persona>/stage/seed_merchant_category_regex_mapping.csv}'
-- With the var unset (the real pipeline) this reads the committed dbt seed exactly
-- as before, so the real seed is never touched.
{% if var('regex_seed_csv', none) %}
  {% set regex_source %}read_csv('{{ var('regex_seed_csv') }}', header=true){% endset %}
{% else %}
  {% set regex_source %}{{ ref('seed_merchant_category_regex_mapping') }}{% endset %}
{% endif %}
select cast(merchant_category as varchar)    as merchant_category
      ,cast(merchant_subcategory as varchar) as merchant_subcategory
      ,cast(regex_match_pat as varchar)      as regex_match_pat
      ,cast(match_priority as integer)       as match_priority
from {{ regex_source }}
