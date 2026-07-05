{{ config(severity='warn')}}
select * 
from {{ ref('rpt_unknown_transactions') }}