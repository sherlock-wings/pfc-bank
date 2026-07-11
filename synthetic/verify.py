#!/usr/bin/env python3
"""Verify the generated demo data the way the dbt pipeline will consume it.

Replicates dim_merchant's regex categorisation against synthetic/out and
asserts zero **UNKNOWN** merchants (the condition assert_no_unknown_merchants
enforces), then prints the category/subcategory shape.
"""
import argparse
from pathlib import Path

import duckdb

HERE = Path(__file__).resolve().parent

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument("--out", default=None,
                help="generated output dir to verify (default: synthetic/out/<persona>)")
ap.add_argument("--persona", default="jordan-rivera",
                help="persona slug, used to locate the default output dir")
args = ap.parse_args()

OUT = Path(args.out) if args.out else HERE / "out" / args.persona
GLOB = str(OUT / "transactions" / "*" / "*" / "*" / "*.json")
SEED = str(OUT / "seed_merchant_category_regex_mapping.csv")

con = duckdb.connect()

con.execute(f"""
create table raw as
with init as (
  select unnest(accounts) as acnt from read_json_auto('{GLOB}')
)
select acnt.name as bank_account_name,
       unnest(acnt.transactions) as t
from init
""")

con.execute("""
create table fact as
select bank_account_name,
       t.id as txn_id,
       t.payee as payee,
       t.description as txn_description,
       md5(coalesce(lower(t.payee),'NULL')||'||'||coalesce(lower(t.description),'NULL')) as key,
       cast(t.amount as decimal(14,2)) as amount,
       to_timestamp(t.posted) as posted_at
from raw
qualify row_number() over (partition by t.id order by to_timestamp(t.posted) desc) = 1
""")

con.execute(f"create table seed as select * from read_csv_auto('{SEED}')")

con.execute("""
create table dim as
with skeleton as (
  select key, lower(payee) as merchant_name, lower(txn_description) as descr,
         count(distinct txn_id) as n, sum(amount) as total
  from fact group by key, lower(payee), lower(txn_description)
)
select s.key, s.merchant_name, s.n, s.total,
       coalesce(r.merchant_category,'**UNKNOWN**') as category,
       coalesce(r.merchant_subcategory,'**UNKNOWN**') as subcategory
from skeleton s
left join seed r on regexp_matches(s.descr, r.regex_match_pat)
qualify row_number() over (partition by s.key order by r.match_priority) = 1
""")

n_txn = con.execute("select count(*) from fact").fetchone()[0]
n_uniq = con.execute("select count(*) from dim").fetchone()[0]
unknown = con.execute("""
  select merchant_name, n from dim where category='**UNKNOWN**' order by n desc
""").fetchall()

print(f"unique txns (deduped) : {n_txn:,}")
print(f"distinct merchant keys: {n_uniq:,}")
print(f"UNKNOWN merchant keys : {len(unknown)}")
if unknown:
    print("  !! unmapped samples:")
    for name, n in unknown[:20]:
        print(f"     {n:4d}  {name}")

print("\ncategory shape (expense $ excludes transfers/payments):")
rows = con.execute("""
  select category, sum(total) as net, count(*) as merchants
  from dim group by category order by net
""").fetchall()
for cat, net, m in rows:
    print(f"  {cat:16s} {net:14,.2f}  ({m} merchant keys)")

assert not unknown, f"FAIL: {len(unknown)} unmapped merchant keys"
print("\nPASS: every merchant maps to a category (assert_no_unknown_merchants would be green)")
