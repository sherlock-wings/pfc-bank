select
      *
  from read_parquet('${data_root}/dashboard_mart/kimball_star/dim_accounts_current.parquet')
 