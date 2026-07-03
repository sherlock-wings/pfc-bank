# Getting comfortable with DuckDB for `nfcu-pipe`

You asked how I'd approach this **without changing any code** — so this is a strategy/orientation
doc, not an implementation. I've grounded every example in the *actual* raw data you have in
`workbench/*.json` so you can copy-paste and see real results.

Before the point-by-point walkthrough, one reframe matters enough to lead with, because it
rewrites two of your seven goals.

---

## The one thing to internalize first: DuckDB is not a server

DuckDB is an **embedded, in-process analytical database** — think "SQLite for analytics,"
not "a small Postgres." That single fact changes how several of your goals map to reality:

- There is **no instance, daemon, service, or port** to run. You install one binary (or a
  Python/library import), and it runs *inside* whatever process opened it (the CLI, Python,
  dbt, Streamlit). "Setting up an instance" just means: install it, and decide whether your
  data lives in memory (`:memory:`) or in a single file on disk (`finances.duckdb`).
- There is **no user system, no roles, no RBAC, no login, no private keys *into the
  database*.** A DuckDB database is one file. Whoever can read that file on the filesystem
  can read everything in it; that's the entire security model. There is nothing to
  authenticate *into*.

So goal #2 as written ("create a user, set RBAC, authenticate into the DB") doesn't exist in
single-file DuckDB. That's not a gap you need to fill — it's a category that doesn't apply.
But the *intent* behind it is real, and it splits into three things that do exist, covered in
goal #2 below.

Everything else on your list is squarely what DuckDB is *great* at.

---

## Your seven goals, reworked

### 1. "Set up a DuckDB instance locally"

Reframed: **install the binary, pick where data lives.**

```bash
# Arch: pacman -S duckdb  |  or the official one-liner:
curl https://install.duckdb.org | sh

duckdb                      # scratch REPL, in-memory, gone on exit
duckdb finances.duckdb      # opens/creates a persistent single-file database
```

That's the whole "instance." In-memory is perfect for *exploring* (you already have the raw
JSON; query it directly). A persistent file is for when you want tables/views to survive
between sessions — e.g. a materialized set of cleaned reports.

Note you already have DuckDB as a dependency path via `dbt-duckdb` later, and the Python
package (`pip install duckdb` / `uv add duckdb`) is the *same engine* — the CLI is just one
front-end. Whatever you learn in the CLI transfers verbatim to Python and dbt.

### 2. "Create a user, set RBAC, set up authentication (private keys, etc.)"

As above, this doesn't map to local DuckDB. What you actually want breaks into three real
concerns:

**(a) Credentials to reach S3 — this is the real "auth," and it's the useful part.**
DuckDB reaches S3 through the `httpfs` extension and a **secret** you register in a session.
The elegant move for you: use the `credential_chain` provider so DuckDB reuses your existing
AWS credential chain (env vars / `~/.aws/credentials` / SSO) — the *same* identity story as
the OIDC role your GitHub Action assumes, just resolved locally instead of in CI. No keys
pasted into SQL.

```sql
INSTALL httpfs;  LOAD httpfs;
CREATE SECRET nfcu (
    TYPE s3,
    PROVIDER credential_chain,   -- pull from the standard AWS chain, no literal keys
    REGION 'us-east-2'           -- pfc-nfcu lives in us-east-2
);
```

If you'd rather not rely on the chain, `PROVIDER config` with explicit `KEY_ID`/`SECRET`
exists — but `credential_chain` keeps this consistent with your "no long-lived keys" stance.

**(b) Protecting the database file itself.** If you want the `.duckdb` file encrypted at
rest (this is financial data), DuckDB supports **encrypted databases** with a key supplied at
attach time (`ATTACH 'finances.duckdb' (ENCRYPTION_KEY '…')`). That's the closest thing to
"private keys into the database," and combined with normal filesystem permissions it's
enough for a single-user local setup.

**(c) If you genuinely want users / RBAC / hosted access / sharing** — that's **MotherDuck**,
the managed cloud DuckDB. It *does* have accounts, access tokens, read scaling, and share
semantics, and it speaks the same SQL. It's the natural upgrade if a dashboard ever needs to
serve more than just you, or you want the DB reachable off your laptop. I'd flag it as a
"later, if needed" option, not a day-one requirement — note it, don't build it yet.

### 3. "Get comfortable with the CLI: objects, queries"

This is where you'll spend your first session. The killer feature for your case: **DuckDB
queries files directly**, so you can start on your existing `workbench/*.json` with zero
loading. From inside `workbench/`:

```sql
-- Peek at the shape DuckDB infers from your raw SimpleFIN dump:
DESCRIBE SELECT * FROM read_json_auto('2026-07-02T040330Z_bd1782950332.json');
-- → columns: errors (VARCHAR[]), accounts (STRUCT[...]) — one row, deeply nested.
```

Your data is **nested** (accounts → transactions arrays), so the core skill to practice is
**UNNEST** — flattening arrays into rows. This single query turns your raw dump into a clean
transaction ledger, and it exercises most of what you need to know:

```sql
WITH acct AS (
  SELECT UNNEST(accounts) AS a
  FROM read_json_auto('2026-07-02T040330Z_bd1782950332.json')
)
SELECT
  a.name                                   AS account,
  UNNEST(a.transactions).id                AS txn_id,
  UNNEST(a.transactions).description        AS description,
  UNNEST(a.transactions).payee              AS payee,
  CAST(UNNEST(a.transactions).amount AS DECIMAL(12,2)) AS amount,      -- amounts are STRINGS
  to_timestamp(UNNEST(a.transactions).posted)         AS posted_at    -- times are epoch secs
FROM acct;
```

Then practice creating persistent objects:

```sql
CREATE TABLE staging_transactions AS <the query above>;   -- a real table
CREATE VIEW  monthly_spend AS                              -- a derived view
  SELECT date_trunc('month', posted_at) AS month,
         account,
         SUM(amount) FILTER (WHERE amount < 0) AS outflow,
         SUM(amount) FILTER (WHERE amount > 0) AS inflow
  FROM staging_transactions GROUP BY 1,2 ORDER BY 1;
```

CLI niceties worth learning early: `.tables`, `.schema`, `DESCRIBE`, `SUMMARIZE <table>`
(instant column-level profiling), `.mode markdown` (pretty output — and, conveniently, the
exact format an LLM likes), `.timer on`.

### 4. "Connect DuckDB to an S3 bucket to query files"

Once the secret from #2 is registered, S3 is just a path — and DuckDB **globs**, which is
perfect for your `YYYY/MM/DD` key layout:

```sql
-- Every raw snapshot you've ever written, as one flat transaction ledger:
WITH raw AS (
  SELECT UNNEST(accounts) AS a
  FROM read_json_auto('s3://pfc-nfcu/transactions/**/*.json')   -- ** = recurse all days
)
SELECT
  a.id AS account_id, a.name AS account,
  t.id AS txn_id, t.description, t.payee,
  CAST(t.amount AS DECIMAL(12,2)) AS amount,
  to_timestamp(t.posted) AS posted_at
FROM raw, UNNEST(a.transactions) AS _(t);
```

**Important reality that ties into your pipeline design:** your extractor writes *overlapping*
snapshots (an 88-day window, multiple times as `balance-date` advances). So the same
`txn_id` appears in many files. Querying `**/*.json` therefore gives you **duplicates by
design** — that's expected, and de-duping is exactly the job you already earmarked for dbt.
The canonical pattern:

```sql
-- Keep one row per transaction: the version from the newest snapshot that saw it.
... QUALIFY row_number() OVER (PARTITION BY txn_id ORDER BY <snapshot_time> DESC) = 1
```

You can recover the snapshot time per row with `filename=true` on `read_json_auto` (adds a
`filename` column) and parsing the `…T…Z_bd<epoch>` key — the `_bd<epoch>` suffix you baked
into the key is your freshness tiebreaker.

### 5. "Create objects in DuckDB and write them back to S3 as JSON"

`COPY … TO` with an `s3://` target. DuckDB writes JSON, Parquet, or CSV back out:

```sql
COPY (SELECT * FROM monthly_spend)
  TO 's3://pfc-nfcu/reports/monthly_spend.json' (FORMAT JSON, ARRAY true);
```

Two notes for your use case:
- For anything you'll re-query, prefer **Parquet** over JSON (`FORMAT PARQUET`) — columnar,
  compressed, typed, and DuckDB reads it far faster than re-parsing JSON. Keep JSON output
  for the human-readable / LLM-facing reports, Parquet for the analytical layer.
- This closes your loop cleanly: **raw JSON in `transactions/` → DuckDB/dbt transforms →
  curated reports back to `reports/`** in the same bucket. Nothing in your extractor changes;
  this is a pure read-side addition.

### 6. "Incorporate dbt, and connect DuckDB to dbt"

This is the natural home for all the cleaning logic, and it's what your plan already calls
for ("cleaning happens later in dbt, not here"). The adapter is **`dbt-duckdb`** — dbt runs
DuckDB in-process, so "connecting" is just a profile, no server:

```yaml
# ~/.dbt/profiles.yml
nfcu:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: finances.duckdb          # or ':memory:' for ephemeral runs
      extensions: [httpfs]
      settings:
        s3_region: us-east-2
      # secrets can be declared here too, so models can read/write s3:// directly
```

A clean, conventional layering that matches your data:
- **staging** (`stg_transactions`): the UNNEST + type-cast + de-dup query from #4. One
  row per real transaction. Reads `s3://…/transactions/**/*.json`.
- **staging** (`stg_accounts`): balances, available-balance, `org`, `balance-date` per
  snapshot — one row per account per snapshot, so you can chart balance history.
- **marts** (`fct_cashflow`, `dim_account`, `monthly_category_summary`): the human-readable
  reports you actually want to look at and feed an LLM.

dbt-duckdb also supports **external materializations** — a model can `materialize` straight
to Parquet/JSON in S3, which is how you'd publish the `reports/` outputs from #5 as part of
`dbt run` rather than as a separate step.

### 7. "Streamlit dashboard — in-memory DuckDB? read from processed JSON?"

Here's the concurrency gotcha to design around up front: **a persistent DuckDB file allows
one writer at a time.** A dashboard is a *reader*, so this is fine — as long as you don't
have dbt writing the same file while Streamlit holds it open. Two clean patterns, in order of
how I'd recommend them:

1. **Dashboard reads the curated Parquet/JSON reports directly** (the `reports/` outputs from
   #5/#6). Streamlit spins up an in-memory DuckDB per session and does
   `SELECT * FROM 's3://pfc-nfcu/reports/*.parquet'` (or local copies). No shared-file
   locking, trivially scalable, and the dashboard stays decoupled from the transform layer.
   This is the one I'd build.
2. **Dashboard opens the `.duckdb` file read-only** (`st.connection` supports DuckDB; open
   with `read_only=True`). Fine for single-user; just ensure dbt isn't writing it live.

If you ever want the dashboard hosted and always-on against a shared DB, that's the
**MotherDuck** case from #2(c) again — Streamlit connects with a token instead of a file
path, and read scaling handles concurrent viewers.

For the **LLM-insights** half of goal #7: the reports are small (you have ~5 accounts and a
few hundred transactions), so the winning move is to have DuckDB/dbt emit *compact,
already-aggregated* artifacts — a monthly category summary, a cashflow-by-account table, a
balances-over-time table — as **markdown or small JSON** (`.mode markdown` / `FORMAT JSON`).
Those drop straight into a context window. Don't feed raw transactions to the model; feed the
curated marts. The same `reports/` objects power both the dashboard and the LLM prompt — one
source of truth, two consumers.

---

## What your data actually looks like (so nothing surprises you)

From `workbench/*.json` (5 accounts: Money Market, Visa cashRewards, Membership Share
Savings, Easy Checking, Mortgage; ~466–486 transactions per snapshot):

| Field | Raw type | Watch out for |
|---|---|---|
| `accounts[].balance`, `available-balance` | **string** | `CAST(… AS DECIMAL(12,2))` before math |
| `accounts[].balance-date` | epoch seconds | `to_timestamp()`; it's your freshness signal |
| `transactions[].amount` | **string**, signed | negatives = outflow; cast to DECIMAL |
| `transactions[].posted`, `transacted_at` | epoch seconds | `posted` may lag `transacted_at` |
| `transactions[].mcc` | **null everywhere** in your data | no merchant-category codes to lean on — categorize off `payee`/`description` |
| `transactions[].memo` | mostly empty strings | don't rely on it |
| `accounts[].holdings` | **empty `[]` everywhere** | no investment holdings; ignore for now, but the field exists if that changes |
| `accounts[].org` | struct (NFCU metadata) | constant; useful as a `dim` attribute |
| top-level `errors` | array | your 88-day-window warning shows up here (`"exceeds recommended range of 45 days…"`) — informational, not a data problem |

Two implications worth internalizing: **categorization must come from `payee`/`description`
text** (mcc is null), and the **Mortgage account has zero transactions** (balance-only), so
any "spend" report should filter it out or handle it as a balance-only account.

---

## The shape of the whole thing

```
  extract.py (unchanged)                DuckDB + dbt (new, read-side)         consumers
  ─────────────────────                 ─────────────────────────────        ─────────
  SimpleFIN ──raw JSON──▶ s3://pfc-nfcu/transactions/YYYY/MM/DD/*.json
                                    │
                                    ▼
                          stg_* (UNNEST, cast, de-dup)
                                    │
                                    ▼
                          marts (cashflow, monthly summary, balances)
                                    │
                       ┌────────────┴────────────┐
                       ▼                          ▼
        s3://pfc-nfcu/reports/*.parquet   s3://pfc-nfcu/reports/*.md/*.json
                       │                          │
                       ▼                          ▼
                 Streamlit dashboard        LLM context window
```

Your existing extractor and its S3 raw layer don't change at all — everything here hangs off
the raw `transactions/` prefix as a new read-side.

---

## Suggested learning path (a couple of evenings)

1. **Evening 1 — local, no S3.** Install DuckDB. Point it at `workbench/*.json`. Practice
   `read_json_auto`, `DESCRIBE`, `SUMMARIZE`, `UNNEST`, casting, `CREATE TABLE/VIEW`. Build
   the flat ledger and one `monthly_spend` view. You'll have learned 80% of goals #1 and #3.
2. **Evening 2 — reach S3.** `INSTALL httpfs`, `CREATE SECRET … credential_chain`, query
   `s3://pfc-nfcu/transactions/**/*.json`, hit the duplicate-rows reality, write the de-dup
   `QUALIFY`, `COPY` a report back to `s3://…/reports/`. Goals #4 and #5, done.
3. **Evening 3 — dbt.** `uv add dbt-duckdb`, write `profiles.yml`, port the SQL from evenings
   1–2 into `stg_` and `marts_` models, `dbt run`. Goal #6.
4. **Later — Streamlit + LLM.** Point Streamlit at the curated `reports/` outputs; wire the
   same outputs into an LLM prompt. Goal #7. Revisit MotherDuck only if/when "just me on my
   laptop" stops being the deployment.

If you want, my suggested first concrete step is a scratch `analysis/` or `dbt/` folder and a
handful of `.sql` files — but per your instruction I've changed nothing; this is the plan
only.
