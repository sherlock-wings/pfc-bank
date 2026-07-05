{{ config(location='s3://pfc-nfcu/dashboard_mart/kimball_star/fact_transactions.parquet') }}

WITH raw AS (
  SELECT UNNEST(accounts) AS acnt
      ,filename
from read_json_auto({{ source('nfcu_raw', 'transactions')}})
)
SELECT
  acnt.id AS bank_account_id,
  acnt.name AS bank_account_name,
  t.id AS txn_id,
  t.description as txn_description,
  md5(coalesce(lower(t.payee), 'NULL')
      || '||' || 
      coalesce(lower(t.description), 'NULL')
  ) as merchant_category_key,
  t.payee,
  CAST(t.amount AS DECIMAL(14,2))       AS amount,
  to_timestamp(t.posted)                AS posted_at_timestamp,
  filename,
  get_current_timestamp() as record_loaded_at_timestamp
FROM raw, UNNEST(acnt.transactions) AS _(t)
qualify row_number() over (
    partition by t.id 
    order     by to_timestamp(t.posted) desc
) = 1

