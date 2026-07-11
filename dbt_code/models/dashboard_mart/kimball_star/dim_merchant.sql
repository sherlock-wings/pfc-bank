{{ config(location=data_path('dashboard_mart/kimball_star/dim_merchant.parquet')) }}

with latest_day_in_data as (
      select max(posted_at_timestamp) as _end
      from {{ ref('fact_transactions') }}
)

,skeleton as (
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

-- infer category/subcategory by matching txn_description against the regex map.
-- a description can hit multiple patterns, so keep only the highest-priority
-- (lowest match_priority) match to guarantee one row per merchant_category_key.
-- unmatched descriptions fall through to '**UNKNOWN**' so new/unmapped
-- merchants still surface in rpt_unknown_transactions.
,categorized as (
select s.merchant_category_key
      ,s.merchant_name
      ,s.first_txn_at_timestamp
      ,s.last_txn_at_timestamp
      ,s.total_transactions
      ,s.total_amount
      ,coalesce(r.merchant_category, '**UNKNOWN**') as merchant_category
      ,coalesce(r.merchant_subcategory, '**UNKNOWN**') as merchant_subcategory
from skeleton s
left join {{ ref('map_merchant_category_regex') }} r
       on regexp_matches(s.txn_description, r.regex_match_pat)
qualify row_number() over (
          partition by s.merchant_category_key
          order by r.match_priority
        ) = 1
)

,last_day as (
    select f.merchant_category_key
          ,sum(f.amount) as total_amount
    from {{ ref('fact_transactions') }} f
    cross join latest_day_in_data l
    where posted_at_timestamp between l._end - interval 1 day
                                  and l._end
    group by merchant_category_key
)

,last_week as (
    select f.merchant_category_key
          ,sum(f.amount) as total_amount
    from {{ ref('fact_transactions') }} f
    cross join latest_day_in_data l
    where posted_at_timestamp between l._end - interval 1 week
                                  and l._end
    group by merchant_category_key
)

,last_month as (
    select f.merchant_category_key
          ,sum(f.amount) as total_amount
    from {{ ref('fact_transactions') }} f
    cross join latest_day_in_data l
    where posted_at_timestamp between l._end - interval 1 month
                                  and l._end
    group by merchant_category_key
)

,last_quarter as (
    select f.merchant_category_key
          ,sum(f.amount) as total_amount
    from {{ ref('fact_transactions') }} f
    cross join latest_day_in_data l
    where posted_at_timestamp between l._end - interval 1 quarter
                                  and l._end
    group by merchant_category_key
)

,last_year as (
    select f.merchant_category_key
          ,sum(f.amount) as total_amount
    from {{ ref('fact_transactions') }} f
    cross join latest_day_in_data l
    where posted_at_timestamp between l._end - interval 1 year
                                  and l._end
    group by merchant_category_key
)

select c.merchant_category_key
      ,c.merchant_name
      ,c.merchant_category
      ,c.merchant_subcategory
      ,c.first_txn_at_timestamp as earliest_txn_at
      ,c.last_txn_at_timestamp as latest_txn_at
      ,c.total_transactions
      ,coalesce(d.total_amount, 0) as amount_past_day
      ,coalesce(w.total_amount, 0) as amount_past_week
      ,coalesce(m.total_amount, 0) as amount_past_month
      ,coalesce(q.total_amount, 0) as amount_past_quarter
      ,coalesce(y.total_amount, 0) as amount_past_year
      ,c.total_amount
      ,get_current_timestamp() as record_updated_at
from categorized c
left join last_day d
       on c.merchant_category_key = d.merchant_category_key
left join last_week w
       on c.merchant_category_key = w.merchant_category_key
left join last_month m
       on c.merchant_category_key = m.merchant_category_key
left join last_quarter q
       on c.merchant_category_key = q.merchant_category_key
left join last_year y
       on c.merchant_category_key = y.merchant_category_key
