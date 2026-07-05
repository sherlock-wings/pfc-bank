{{ config(materialized='external', format='parquet', location='s3://pfc-nfcu/stage/map_merchant_category.parquet') }}
-- passthrough model required when reading from seeds
-- seeds to not support external table strategy; need a passthrough node
select md5(coalesce(lower(merchant_name), 'NULL')
           || '||' ||
           coalesce(lower(description), 'NULL')
      ) as merchant_category_key
      ,merchant_name
      ,description as txn_description
      ,merchant_category
      ,merchant_subcategory
      ,try_cast(last_updated_timestamp as timestamptz) as last_updated_timestamp
from {{ ref('seed_merchant_category') }}
