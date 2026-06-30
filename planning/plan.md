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
- **Runner:** GitHub Actions cron `0 23 * * *`.
- **Fetch:** `GET <access-url>/accounts` (HTTP Basic auth from the SimpleFIN access URL).
- **Store:** write the response **verbatim** to S3. No transform, no schema, no dedupe.
- **Bucket/key:** `pfc-nfcu/transactions/YYYY/MM/DD/yyyy-mm-ddThhmmss.json`.
- **AWS auth:** GitHub OIDC assumes a scoped IAM role (`s3:PutObject` on `pfc-nfcu` only). No stored keys.
- **Alerting:** email on failure or empty pull.
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
