# nfcu-pipe plan

## Goal
Daily, unattended: pull NFCU account data and dump it **raw** to S3. Cleaning happens later in dbt, not here.

## Data access
Use **SimpleFIN Bridge** ($15/yr aggregator). NFCU is confirmed supported.

Rejected:
- **Plaid** — not free for daily use (free tier caps at ~200 live calls, then per-call billing).
- **OFX/Direct Connect** — NFCU doesn't offer it. Dead end.
- **Web scraping** — fights NFCU MFA + bot detection every run. Fallback only.

## Architecture
- **Runner:** GitHub Actions cron every 90 min, clock-anchored to 00:00 (16 slots/day,
  first 00:00, last 22:30; two cron entries since cron can't express a 90-min interval).
  Best-effort. Each run is one attempt; the next slot is the retry. **Freshness-aware
  guard:** the script keeps pulling until it captures a refresh whose `balance-date` is
  dated today, then stops — so a refresh landing at any hour (MX's refresh time drifts)
  is caught within ~90 min. Actual attempts vary 1–16/day depending on when the refresh
  lands; the 16-slot ceiling leaves healthy margin under SimpleFIN's 24/day cap.
- **Fetch:** `GET <access-url>/accounts?start-date=<90d ago>` (HTTP Basic auth from the
  SimpleFIN access URL). See `ingestion_setup.md` for the 90-day request-span vs.
  history-depth caveat.
- **Store:** write the response **verbatim** to S3, but only when `balance-date` advances
  past the last stored pull (skips redundant re-writes). No transform/schema/dedupe.
- **Bucket/key:** `pfc-nfcu/transactions/YYYY/MM/DD/yyyy-mm-ddThhmmssZ_bd<balance-date-epoch>.json`.
  The `_bd<epoch>` suffix lets the guard judge freshness from keys alone (ListBucket only).
- **AWS auth:** GitHub OIDC assumes a scoped IAM role. No stored keys. Needs
  `s3:PutObject` (write the dump) **and** `s3:ListBucket` (guard reads keys for
  balance-dates) on `pfc-nfcu`. No `s3:GetObject` required.
- **Alerting:** quiet during the day's hourly retries; email once only if no successful
  fetch by `ALERT_CUTOFF_HOUR_UTC` (default 20:00 UTC). A fetch that succeeds but isn't
  yet fresh is not a failure — it just retries next hour.
- **Language:** Python.

## Phase 0 — no-invest test ($0)
Prove everything except the NFCU link, using SimpleFIN's free demo token.

1. Claim demo token → exchange for demo access URL.
2. Python script: fetch `/accounts`, dump raw JSON to S3 at the real key path.
3. Run it in GitHub Actions on the real cron, authed via OIDC.
4. Trigger the failure path → confirm email arrives.

Proves: SimpleFIN protocol, raw dump, S3 write, OIDC, cron, alerting.
Leaves unproven: NFCU-specific data (needs payment + live link).

## Phase 1 — go live ($15/yr)
1. Subscribe to SimpleFIN; link NFCU (one-time MFA).
2. Swap demo access URL for the real one (stored as secret `SIMPLEFIN_ACCESS_URL`).
3. Confirm real NFCU JSON lands in S3.

## Known risk
NFCU actively fights aggregators and forces periodic re-auth (it broke all Plaid links in May 2023). The pipeline is **not** fully hands-off — alerting tells you when to re-link.

## Deliverables
- Python fetch+dump script.
- `.github/workflows/daily.yml`.
- IAM role + OIDC trust (bucket already exists).
