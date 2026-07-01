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

First live NFCU pull (2026-06-30): all 5 accounts and current balances came back, but **every transaction was stamped at one identical timestamp ~24h prior** — MX's initial-sync placeholder, not real posting dates. The request already covered the full 90 days back; NFCU/MX simply returned nothing older. Production returned no warning in `errors`.

Working hypothesis: **history accumulates forward from link date** — there is no pre-link backfill, so depth grows ~1 day per day from signup. Consistent with the first pull, not yet confirmed.

Resolve it directly (don't wait 90 days): request a past-only window that ends *before* the link date.

```bash
S=$(date -d '2026-04-25' +%s); E=$(date -d '2026-06-25' +%s)
curl -s "$ACCESS_URL/accounts?start-date=$S&end-date=$E" | python3 -m json.tool
```

- Empty transactions → confirmed: no pre-link history; depth only builds forward.
- Non-empty → history exists; keep requesting it.

Design consequence if history only builds forward: the 90-day window is **not** a real backfill backstop yet. **A missed run can permanently lose any data older than the next pull returns**, so until depth is proven, cadence must never miss a day (or backfill must be handled another way).
