with skeleton as (
select payee
      ,min(posted_at_timestamp) as first_txn_at_timestamp
      ,max(posted_at_timestamp) as last_txn_at_timestamp
      ,count(distinct txn_id) as total_transactions
from {{ ref('fact_transactions') }}
group by payee
)

,last_day as (
    select payee, sum(amount) as total_spend
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('day', get_current_timestamp()) - interval 1 day
                                  and date_trunc('day', get_current_timestamp()) 
    group by payee
)

,last_week as (
    select payee, sum(amount) as total_spend
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('week', get_current_timestamp()) - interval 1 week
                                  and date_trunc('week', get_current_timestamp()) 
    group by payee
)

,last_month as (
    select payee, sum(amount) as total_spend
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('month', get_current_timestamp()) - interval 1 month
                                  and date_trunc('month', get_current_timestamp()) 
    group by payee
)

,last_quarter as (
    select payee, sum(amount) as total_spend
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('quarter', get_current_timestamp()) - interval 1 quarter
                                  and date_trunc('quarter', get_current_timestamp()) 
    group by payee
)

,last_year as (
    select payee, sum(amount) as total_spend
    from {{ ref('fact_transactions') }}
    where posted_at_timestamp between date_trunc('year', get_current_timestamp()) - interval 1 year
                                  and date_trunc('year', get_current_timestamp()) 
    group by payee
)

select lower(s.payee) as payee
      ,s.first_txn_at_timestamp
      ,s.last_txn_at_timestamp
      ,s.total_transactions
      ,e.merchant_category
      ,e.merchant_subcategory
      ,d.total_spend as spend_past_day
      ,w.total_spend as spend_past_week
      ,m.total_spend as spend_past_month
      ,q.total_spend as spend_past_quarter
      ,y.total_spend as spend_past_year
      ,get_current_timestamp() as record_updated_at
from skeleton s 
left join last_day d 
       on s.payee = d.payee
left join last_week w 
       on s.payee = w.payee
left join last_month m 
       on s.payee = m.payee
left join last_quarter q 
       on s.payee = q.payee
left join last_year y 
       on s.payee = y.payee
left join {{ ref('seed_merchant_category')}} e 
       on e.payee = s.payee

