{#
  data_path('subdir/file.parquet') -> '<data_root>/subdir/file.parquet'

  Every S3 read/write path in the project is anchored to a single `data_root`
  var (default 's3://pfc-nfcu', set in dbt_project.yml). Point a whole pipeline
  run at a different persona/demo by overriding it, e.g.

    dbt build --vars '{data_root: s3://pfc-nfcu/demo/jordan-rivera}'

  and the raw source, stage, and dashboard_mart layers all move together.
#}
{% macro data_path(relative) %}
  {{- return(var('data_root').rstrip('/') ~ '/' ~ relative.lstrip('/')) -}}
{% endmacro %}
