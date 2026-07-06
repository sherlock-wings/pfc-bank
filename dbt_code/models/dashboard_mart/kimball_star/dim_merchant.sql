{{ config(location='s3://pfc-nfcu/dashboard_mart/kimball_star/dim_merchant.parquet') }}

with skeleton as (
select merchant_category_key
      ,lower(payee) as merchant_name
      ,lower(txn_description) as txn_description
      ,min(posted_at_timestamp) as first_txn_at_timestamp
      ,max(posted_at_timestamp) as last_txn_at_timestamp
      ,count(distinct txn_id) as total_transactions
      ,sum(amount) as total_amount
from {{ ref('fact_transactions') }}
group by merchant_category_key, lower(payee), lower(txn_description)
)

,last_day as (
    select merchant_category_key
          ,lower(payee) as merchant_name
          ,lower(txn_description) as txn_description
          ,sum(amount) as total_amount
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('day', get_current_timestamp()) - interval 1 day
                                  and date_trunc('day', get_current_timestamp()) 
    group by merchant_category_key, lower(payee), lower(txn_description)
)

,last_week as (
    select merchant_category_key
          ,lower(payee) as merchant_name
          ,lower(txn_description) as txn_description
          ,sum(amount) as total_amount
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('week', get_current_timestamp()) - interval 1 week
                                  and date_trunc('week', get_current_timestamp()) 
    group by merchant_category_key, lower(payee), lower(txn_description)
)

,last_month as (
    select merchant_category_key
          ,lower(payee) as merchant_name
          ,lower(txn_description) as txn_description
          ,sum(amount) as total_amount
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('month', get_current_timestamp()) - interval 1 month
                                  and date_trunc('month', get_current_timestamp()) 
    group by merchant_category_key, lower(payee), lower(txn_description)
)

,last_quarter as (
    select merchant_category_key
          ,lower(payee) as merchant_name
          ,lower(txn_description) as txn_description
          ,sum(amount) as total_amount
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('quarter', get_current_timestamp()) - interval 1 quarter
                                  and date_trunc('quarter', get_current_timestamp()) 
    group by merchant_category_key, lower(payee), lower(txn_description)
)

,last_year as (
    select merchant_category_key
          ,lower(payee) as merchant_name
          ,lower(txn_description) as txn_description
          ,sum(amount) as total_amount
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('year', get_current_timestamp()) - interval 1 year
                                  and date_trunc('year', get_current_timestamp()) 
    group by merchant_category_key, lower(payee), lower(txn_description)
)

select s.merchant_category_key
      ,s.merchant_name
      ,s.txn_description
      ,case 
         when e.txn_description ilike '%pos adjustment%'
         then 'payments'
         else e.merchant_category 
       end as merchant_category
      ,case 
         when e.txn_description ilike '%pos adjustment%'
         then 'refunds'
         else e.merchant_subcategory 
       end as merchant_subcategory
      ,s.first_txn_at_timestamp as earliest_txn_at
      ,s.last_txn_at_timestamp as latest_txn_at
      ,s.total_transactions
      ,coalesce(d.total_amount, 0) as amount_past_day
      ,coalesce(w.total_amount, 0) as amount_past_week
      ,coalesce(m.total_amount, 0) as amount_past_month
      ,coalesce(q.total_amount, 0) as amount_past_quarter
      ,coalesce(y.total_amount, 0) as amount_past_year
      ,s.total_amount
      ,get_current_timestamp() as record_updated_at
from skeleton s 
left join last_day d 
       on s.merchant_category_key = d.merchant_category_key
left join last_week w 
       on s.merchant_category_key = w.merchant_category_key
left join last_month m 
       on s.merchant_category_key = m.merchant_category_key
left join last_quarter q 
       on s.merchant_category_key = q.merchant_category_key
left join last_year y 
       on s.merchant_category_key = y.merchant_category_key
left join {{ ref('map_merchant_category')}} e 
       on e.merchant_category_key = s.merchant_category_key