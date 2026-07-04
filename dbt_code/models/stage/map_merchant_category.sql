{{ config(materialized='external', format='parquet', location='s3://pfc-nfcu/stage/map_merchant_category.parquet') }}
-- passthrough model required when reading from seeds
-- seeds to not support external table strategy; need a passthrough node
select md5(merchant_name) as merchant_key
      ,merchant_name
      ,merchant_category
      ,merchant_subcategory
      ,try_cast(last_updated_timestamp as timestamptz) as last_updated_timestamp
from {{ ref('seed_merchant_category') }}
