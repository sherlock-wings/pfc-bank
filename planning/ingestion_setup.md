# Ingestion setup

How to get an access URL, pull data with it, and figure out how often pulling is worth it.

## 1. Get an access URL (one-time per link)

The access URL is a permanent credential with `user:pass` baked in. Treat it like a password.

1. At <https://bridge.simplefin.org>, subscribe and **Connect** Navy Federal. This hands off to the MX login widget; enter NFCU creds + MFA. One-time, interactive.
2. Under **Connect an app**, copy the **Setup Token** (one long base64 blob, single-use).
3. Exchange it for the access URL:

   ```bash
   SETUP_TOKEN='paste-token-here'
   CLAIM_URL=$(printf '%s' "$SETUP_TOKEN" | base64 -d)   # mac: base64 --decode
   ACCESS_URL=$(curl -s -X POST "$CLAIM_URL")
   echo "$ACCESS_URL"   # https://<user>:<pass>@bridge.simplefin.org/simplefin
   ```

The printed value is what goes in the `SIMPLEFIN_ACCESS_URL` secret. Re-link (repeat steps 1–3) only when NFCU forces re-auth.

## 2. Pull data

```bash
curl -s "$ACCESS_URL/accounts" | python3 -m json.tool > nfcu_raw.json
```

Useful query params on `/accounts`:

| Param | Effect |
|---|---|
| `start-date=<epoch>` | Only transactions on/after this time |
| `end-date=<epoch>` | Only transactions on/before this time |
| `pending=1` | Include not-yet-posted transactions |
| `balances-only=1` | Balances only, skip transactions (cheap probe) |

Widen the window (last 90 days):

```bash
curl -s "$ACCESS_URL/accounts?start-date=$(date -d '90 days ago' +%s)" > nfcu_raw.json
```

## 3. Figure out the right pull cadence

Polling faster than the bank refreshes just returns the same data. Two things to measure:

**How fresh is the data (sets cadence).** MX refreshes each account ~once/24h, at a drifting time of day. Confirm before trusting it:

- Pull `balances-only=1` every hour for a day. Watch `balance-date` (and newest `posted`). It only moves when the bank actually refreshed.
- If `balance-date` changes ~once/day → daily cron is enough; more often is wasted calls.
- If it never moves across days → the link is stale; that's an alert condition, not a reason to poll harder.

**How far back data goes (sets history depth + backfill need).** Pull with an old `start-date` and find the oldest `posted` returned. If it stops well short of your `start-date`, that's the real history limit — the daily dumps accumulate true history past that point.

Net: pick the slowest cadence that doesn't miss a refresh. Start at daily, only go faster if `balance-date` proves the bank updates faster.

## 4. Known limitation: 90-day request ≠ 90 days returned

Two different limits, per the [developer guide](https://beta-bridge.simplefin.org/info/developers):
- **Request span cap:** a single `/accounts` call may span at most 90 days (`end-date` − `start-date`). This is the *width of the question*, not a promise of data.
- **History available:** *"varies for each institution"* — SimpleFIN guarantees no depth for NFCU.
- **Rate limit:** 24 requests/day, so you cannot poll faster than ~hourly.

**RESOLVED (2026-07-01): deep backfill is real.** A pull ~2 days after linking returned
5 accounts and **real, correctly-dated history spanning ~87 days** (2026-04-03 → 2026-06-29;
410 transactions on checking alone). So NFCU/MX *does* serve the full window — the
earlier "forward-accumulation only" worry is disproven, and the 90-day window is a
genuine backfill backstop. A missed run is recovered by the next pull.

(For the record — the first pull on 2026-06-30, hours after linking, returned everything
stamped at one placeholder timestamp: MX's initial-sync artifact. Real dated history
appeared within ~2 days as MX finished backfilling.)

### The 90-day cap warning is harmless
Requesting *exactly* 90 days makes the server return `errors: ["...exceeds limit of 90
days and was capped."]` — a **warning, not a failure**. Data is still returned in full;
`is_empty()` ignores `errors`, so the guard and alerting are unaffected. To keep `errors`
empty on healthy pulls (so a non-empty array stays a real signal), `extract.py` requests
`PULL_WINDOW_DAYS = 88` — just under the cap.
