with first_txn as (
    select min(posted_at_timestamp::date) as txn_at 
    from pfc_bank.rpt_expenses_detail
)
select * from pfc_bank.rpt_daily_overunder
where calendar_date >= (select txn_at from first_txn)