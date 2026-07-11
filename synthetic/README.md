# Synthetic demo dataset

A repeatable, **fully fictional** clone of the real SimpleFIN dataset, so the
project can be shown in a portfolio without exposing any real bank data.

It reproduces the *shape* of the real profile — a five-account credit-union
household (checking, money-market savings, membership share savings, a rewards
credit card, and a mortgage), biweekly W-2 income, cost-of-living spend, debt
service, and discretionary categories — for an **imaginary person** (`JORDAN A
RIVERA`), imaginary businesses, and imaginary towns. No real name, employer,
merchant, or location appears anywhere.

## Files

| file | role |
|------|------|
| `persona.yaml` | the imaginary person: identity, accounts, income, recurring flows, timeline. Tune the numbers here. |
| `merchants.yaml` | **single source of truth** — the fake merchant catalog + structural bank descriptors. Drives both the JSON descriptions *and* the regex seed. |
| `generate.py` | builds one master ledger, emits SimpleFIN snapshots + a regenerated regex seed. Deterministic (fixed RNG seed). |
| `verify.py` | replicates dbt's `dim_merchant` categorisation and asserts **zero `**UNKNOWN**`** merchants. |
| `out/` | generated output (git-ignored; regenerate any time). |

## Why the merchant catalog is the source of truth

The dbt layer categorises transactions by **regex-matching the `description`
string** (`dim_merchant.sql` → `seed_merchant_category_regex_mapping.csv`).
Anything unmatched becomes `**UNKNOWN**` and trips `assert_no_unknown_merchants`.

So fake transactions and the regex seed are coupled. `generate.py` derives
**both** from `merchants.yaml`: every merchant's `token` is embedded in the
descriptions *and* emitted as its regex alternate. Change a merchant in one
place and both sides move together — the demo pipeline always stays green.

## Usage

```bash
# generate into synthetic/out/ (deterministic — identical every run)
uv run python synthetic/generate.py

# prove every merchant categorises (no **UNKNOWN**) + print the category shape
uv run python synthetic/verify.py
```

Output: ~2,200 unique transactions across 31 monthly snapshot files
(~6k rows with realistic overlap for the dbt dedup to collapse) — well under
the 100k target.

The snapshots emulate real SimpleFIN pulls: each file carries a trailing
88-day window and a balance-date, transaction ids are **stable across
overlapping snapshots**, and the newest file is dated `timeline.as_of_date`
with the configured end balances (the only balances `dim_accounts` keeps).

## Pointing the pipeline at the demo data

The real dbt source reads `s3://pfc-nfcu/transactions/*/*/*/*.json`. Two ways
to run the demo:

1. **Local**: upload `synthetic/out/transactions/**` to a demo bucket/prefix
   (e.g. `pfc-nfcu-demo`) and point `models/sources.yml` `external_location`
   there, or override with a local glob for a no-credentials run.
2. **Swap the seed**: to publish the demo you also need the demo regex seed in
   place of the real one (the real seed references real merchant names):

   ```bash
   # ONLY on a machine that is NOT running your real pipeline:
   uv run python synthetic/generate.py --write-dbt-seed
   ```

   This overwrites `dbt_code/seeds/seed_merchant_category_regex_mapping.csv`
   with the fake catalog's seed. Keep your real seed private (it maps your real
   merchants); the demo seed maps only the fictional ones.

   **Why the "not your real pipeline" warning:** the demo seed's regexes only
   match the fictional merchants. If it replaces the real seed on your
   production machine, your *real* transactions no longer match any pattern,
   fall through to `**UNKNOWN**`, and trip `assert_no_unknown_merchants` — i.e.
   it breaks your real pipeline.

## Reshaping the demo

- **Category mix / "shape"** — adjust merchant `weight`s in `merchants.yaml`
  and `discretionary.purchases_per_week_mean` in `persona.yaml`.
- **Balances / income / bills** — edit `persona.yaml`.
- **History length** — change `timeline.start_date` / `as_of_date` /
  `snapshot_cadence_days`.
- **Different seed** — change `seed:` in `persona.yaml` for a different (still
  deterministic) draw.
