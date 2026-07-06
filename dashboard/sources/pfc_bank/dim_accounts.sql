select
      *
  from read_parquet('s3://pfc-nfcu/dashboard_mart/kimball_star/dim_accounts.parquet')
 