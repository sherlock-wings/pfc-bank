{{ config(materialized='external', format='parquet', location='s3://pfc-nfcu/stage/stg_merchant_category.parquet') }}
-- passthrough model required when reading from seeds
-- seeds to not support external table strategy; need a passthrough node
select * from {{ ref('seed_merchant_category') }}
