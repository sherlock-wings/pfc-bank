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

## Frictionless re-link (SHELL PLAN — revisit later)

**Goal:** when NFCU forces a re-auth (inevitable, see Known risk), make recovery as
close to a phone-only, one-tap action as possible.

**The irreducible manual step:** re-authenticating NFCU is an MFA flow at SimpleFIN
Bridge. It is interactive by design (that's the security boundary) and *cannot* be fully
automated. Best case is "open a link on your phone, complete MFA, done." So the target
is a *mobile-browser* re-auth, not literally a GitHub button — GitHub can't do the MFA.

**The key open question that decides everything (verify next time it breaks):**
Does the SimpleFIN **access URL survive a re-auth**, or is a new one issued?
- **If it survives** → re-linking is purely: phone → <https://bridge.simplefin.org> →
  tap the broken NFCU connection → MFA → done. No GitHub, no secret rotation. Optionally
  trigger the workflow from the **GitHub mobile app** (`workflow_dispatch`) to confirm the
  fix immediately instead of waiting for the next scheduled slot. This is already ~one-tap.
- **If it rotates** → also need to update the `SIMPLEFIN_ACCESS_URL` secret, which is the
  real friction (editing a GitHub secret from a phone is painful). Options to explore:
  - Re-run the setup-token → access-URL exchange, then update the secret via the GitHub
    API from a small helper (Action or tiny endpoint) holding a scoped PAT. Adds moving
    parts + a stored credential — only worth it if re-auth is frequent.
  - Or accept a rare manual secret edit.

**Next action:** the next time the link breaks (or by deliberately re-authing once),
observe whether the access URL changes. That single observation picks the branch above.
Until then this stays a stub.

**Nice-to-haves for later:** a `workflow_dispatch`-only "test link now" run that pulls and
reports health without waiting for cron; a bookmark/shortcut on the phone home screen
straight to the NFCU connection in SimpleFIN Bridge.
