{{ config(materialized='external', format='parquet', location='s3://pfc-nfcu/stage/map_merchant_category_regex.parquet') }}
-- passthrough model required when reading from seeds
-- seeds do not support external table strategy; need a passthrough node
select cast(merchant_category as varchar)    as merchant_category
      ,cast(merchant_subcategory as varchar) as merchant_subcategory
      ,cast(regex_match_pat as varchar)      as regex_match_pat
      ,cast(match_priority as integer)       as match_priority
from {{ ref('seed_merchant_category_regex_mapping') }}
