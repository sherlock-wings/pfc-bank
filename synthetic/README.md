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
| `personas/<slug>/persona.yaml` | one imaginary person: identity, accounts, income, recurring flows, timeline. Tune the numbers here. |
| `personas/<slug>/merchants.yaml` | **single source of truth** for that persona — the fake merchant catalog + structural bank descriptors. Drives both the JSON descriptions *and* the regex seed. |
| `generate.py` | builds one master ledger, emits SimpleFIN snapshots + a regenerated regex seed + a regenerated payrate seed. Deterministic (fixed RNG seed). `--persona <slug>` picks which persona. |
| `verify.py` | replicates dbt's `dim_merchant` categorisation and asserts **zero `**UNKNOWN**`** merchants. |
| `out/<slug>/` | generated output per persona (git-ignored; regenerate any time). |
| `../run-demo.sh` | one-command persona mode: generate → upload → dbt → dashboard. See below. |

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
# generate into synthetic/out/<persona>/ (deterministic — identical every run)
uv run python synthetic/generate.py --persona jordan-rivera

# prove every merchant categorises (no **UNKNOWN**) + print the category shape
uv run python synthetic/verify.py --persona jordan-rivera
```

Output: ~2,200 unique transactions across 31 monthly snapshot files
(~6k rows with realistic overlap for the dbt dedup to collapse) — well under
the 100k target.

The snapshots emulate real SimpleFIN pulls: each file carries a trailing
88-day window and a balance-date, transaction ids are **stable across
overlapping snapshots**, and the newest file is dated `timeline.as_of_date`
with the configured end balances (the only balances `dim_accounts` keeps).

## Persona mode: end-to-end run on localhost

The whole pipeline is anchored to a single `data_root` prefix (dbt var +
`macros/data_path.sql`; the Evidence dashboard reads `${data_root}` from
`EVIDENCE_VAR__data_root`). By default `data_root` is `s3://pfc-nfcu` — your
real pipeline — and nothing here changes that. Persona mode only *overrides*
it, per run, to a per-persona subtree at `s3://pfc-nfcu/demo/<slug>/`.

### Prerequisites

- **`uv`** — runs the Python generator + dbt (deps come from `pyproject.toml`).
- **AWS credentials** on the default chain (same one the real pipeline uses),
  region `us-east-2`, with write access to `s3://pfc-nfcu/demo/*`.
- **Node ≥ 18 + npm** — only for the dashboard (step E).

### The one command

```bash
./run-demo.sh ls-persona             # personas you can run
./run-demo.sh jordan-rivera          # runs stages B–E below, ends on localhost
./run-demo.sh jordan-rivera --no-serve  # stop after dbt (stages B–D), no dashboard
./run-demo.sh reset jordan-rivera    # wipe this persona everywhere, then rebuild B–E
./run-demo.sh reset jordan-rivera --yes # same, but skip the delete confirmation
./run-demo.sh check jordan-rivera    # validate the persona's YAML, run nothing
```

`reset` (or `<slug> --reset`) is the tweak-and-rerun button: it recursively
deletes the persona's whole S3 subtree (`s3://<bucket>/<demo-prefix>/<slug>/`),
the local `synthetic/out/<slug>/`, and the dashboard's Evidence cache, then runs
the normal pipeline from scratch. Use it after editing the persona's YAML — a
plain run only reconciles `transactions/`, so stale dbt output under `stage/` and
`dashboard_mart/` can survive; `reset` guarantees a clean slate. The delete is
always scoped to the demo prefix (never the bucket root or your real data) and
prompts for confirmation unless you pass `--yes`.

That's the whole demo. The rest of this section is the same run **done by hand**,
so you can see (or debug) each stage.

### Stage A — pick or create a persona

```bash
./run-demo.sh ls-persona             # what's available
./run-demo.sh new casey-brooks        # optional: scaffold a copy of jordan-rivera
# then edit personas/casey-brooks/{persona,merchants}.yaml so it's nobody real,
# and change `seed:` for a fresh deterministic draw.
```

For the rest of the walkthrough, set the two values everything else derives from:

```bash
SLUG=jordan-rivera
DATA_ROOT=s3://pfc-nfcu/demo/$SLUG
```

### Validation — catch a broken persona before it runs

`persona.yaml` refers to merchants in `merchants.yaml` **by token string**, so a
rename in one file but not the other (e.g. the electric utility) makes the
generator fail. `synthetic/validate.py` checks that contract — every recurring
merchant token exists, every required account role is present, dates parse,
tokens are regex-safe, the random-draw pools aren't empty, and the YAML is
well-formed — and reports each problem with a file-scoped, plain-English message
(and a "did you mean…?" for near-miss tokens) instead of a `KeyError` traceback.

```bash
uv run python synthetic/validate.py --persona "$SLUG"   # or: ./run-demo.sh check "$SLUG"
```

It runs automatically at the top of `generate.py` and, in `run-demo.sh`, **before
the `--reset` wipe** — so a persona that can't be demoed never destroys good S3
data. *Errors* block the run; *warnings* (e.g. a category outside the dashboard
taxonomy) let it proceed but flag likely mistakes.

### Stage B — generate + verify transactions

```bash
uv run python synthetic/generate.py --persona "$SLUG"
uv run python synthetic/verify.py   --persona "$SLUG"   # expect: UNKNOWN keys 0, PASS
```

Writes `synthetic/out/$SLUG/transactions/**`,
`synthetic/out/$SLUG/seed_merchant_category_regex_mapping.csv`, and
`synthetic/out/$SLUG/seed_payrate.csv`.

### Stage C — upload to the persona's S3 prefix

```bash
aws s3 sync synthetic/out/$SLUG/transactions/ "$DATA_ROOT/transactions/" --delete
aws s3 cp   synthetic/out/$SLUG/seed_merchant_category_regex_mapping.csv \
            "$DATA_ROOT/stage/seed_merchant_category_regex_mapping.csv"
aws s3 cp   synthetic/out/$SLUG/seed_payrate.csv \
            "$DATA_ROOT/stage/seed_payrate.csv"
```

### Stage D — run the dbt pipeline against the persona

```bash
cd dbt_code
uv run dbt build \
  --vars "{data_root: '$DATA_ROOT', \
           regex_seed_csv: '$DATA_ROOT/stage/seed_merchant_category_regex_mapping.csv', \
           payrate_seed_csv: '$DATA_ROOT/stage/seed_payrate.csv'}"
cd ..
```

`data_root` relocates every read/write (raw source, stage, dashboard_mart) into
the persona subtree; `regex_seed_csv` and `payrate_seed_csv` make the stage
models read *this persona's* regex map and payrate from S3 instead of the
committed seeds. With none of these vars set (your real pipeline) dbt
reads/writes `s3://pfc-nfcu/...` and the committed seeds, exactly as before. A
green `assert_no_unknown_merchants` confirms the persona categorised.

### Stage E — deploy the Evidence dashboard to localhost

```bash
echo "EVIDENCE_VAR__data_root=$DATA_ROOT" > dashboard/.env.local  # overrides the committed .env default
cd dashboard
npm install        # first run only
npm run sources    # pull the persona's dashboard_mart parquet from S3
npm run dev        # serves the dashboard — open the URL it prints (default http://localhost:3000)
```

`.env.local` is git-ignored and wins over the committed `dashboard/.env`, so the
dashboard reads the persona's marts, name, and address. See "Switching back to
real data" below to return to your own data. This localhost dashboard is never
deployed; your real site is deployed separately by CI.

### Switching back to real data

`dashboard/.env.local` is the single **active override** slot. `run-demo.sh`
writes the persona's values there; to go back to your real data, run:

```bash
./run.sh             # restore real config, then dbt build + serve on localhost
```

`run.sh` copies `dashboard/.env.real` (git-ignored — your real `data_root`,
name, and address) over `.env.local`, so the page shows *your* data again.
Because both scripts just rewrite `.env.local`, **whichever you run last wins** —
that's the switch. (Deleting `.env.local` alone is *not* enough: it falls back to
the committed `.env`, which holds generic placeholders, not your real values.)

**Your deployed site is unaffected by any of this.** The committed `.env` ships
only placeholders; the CI deploy (`.github/workflows/deploy_dashboard.yml`)
injects your real name/address from the GitHub `dev`-environment variables
`DASHBOARD_FAMILY_NAME` / `DASHBOARD_HOME_ADDRESS` into `.env.local` at build
time, and always reads your real `data_root` from the committed `.env`. So
`bank.<domain>` keeps serving *your* information regardless of local persona runs.
**One-time setup:** add those two variables under the repo's `dev` environment
(Settings → Environments → dev → Variables), matching `dashboard/.env.real`.

### Notes

**The seeds stay isolated.** Each persona's regex map and payrate are generated
alongside its transactions and read from *its* S3 prefix via the
`regex_seed_csv` / `payrate_seed_csv` vars — so the committed dbt seeds (which
carry your real merchants and employer) are never touched. The legacy
`--write-dbt-seed` flag still exists for publishing, but persona mode does not
use it and never overwrites your seeds.

**Overridable env:** `PFC_BUCKET` (default `pfc-nfcu`), `PFC_DEMO_PREFIX`
(default `demo`) change the `s3://<bucket>/<prefix>/<slug>/` root `run-demo.sh`
uses.

## Reshaping a persona

Edit the files under `personas/<slug>/` (a new persona starts as a copy of
another via `./run-demo.sh new <slug>`):

- **Category mix / "shape"** — adjust merchant `weight`s in `merchants.yaml`
  and `discretionary.purchases_per_week_mean` in `persona.yaml`.
- **Balances / income / bills** — edit `persona.yaml`. `income.employer_display`,
  `income.employer_address`, and `income.net_paycheck` also drive the
  regenerated `seed_payrate.csv` (`generate.py`'s `emit_payrate`).
- **Dashboard labels** — `identity.family_name` sets the page title
  (`{family_name} Family Finances :)`) and `identity.home_address` sets the
  Housing card's "Mortgage on …" label. Both are optional: omit `family_name`
  to derive it from `display_name`, and omit `home_address` to auto-generate a
  realistic (invented) street address from `seed`. They reach the Evidence
  dashboard as `EVIDENCE_VAR__*` values (like `data_root`) that `run-demo.sh`
  writes into `dashboard/.env.local`; see `synthetic/persona_meta.py`.
- **History length** — change `timeline.start_date` / `as_of_date` /
  `snapshot_cadence_days`.
- **Different seed** — change `seed:` in `persona.yaml` for a different (still
  deterministic) draw.
