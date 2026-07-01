#!/usr/bin/env python3
"""Fetch raw account data from SimpleFIN and dump it verbatim to S3."""
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit, urlunsplit

import boto3
import requests

# Each stored object embeds the newest balance-date it captured, so the guard
# can reason about freshness from object keys alone (ListBucket, no GetObject).
BD_KEY_RE = re.compile(r"_bd(\d+)\.json$")

# Every run re-fetches a wide window so a missed/dropped run is backfilled by
# the next success. Dedup happens later in dbt, not here. SimpleFIN caps the
# request span at 90 days; requesting *exactly* 90 trips a "capped" warning in
# `errors` on every pull (timing tips the span just over 90). Staying a couple
# days under keeps `errors` empty on healthy pulls, so a non-empty `errors`
# array stays a meaningful signal instead of noise everyone learns to ignore.
PULL_WINDOW_DAYS = int(os.environ.get("PULL_WINDOW_DAYS", "88"))

# Best-effort schedule (cron fires every ~90 min): each run is one attempt, the
# next slot is the retry. We keep pulling until we capture a refresh dated today
# (balance-date advanced), then stop — so a refresh landing any time of day is
# caught within ~90 min regardless of drift. Only fail loudly (alert) if the day
# reaches the cutoff with no successful fetch at all.
ALERT_CUTOFF_HOUR_UTC = int(os.environ.get("ALERT_CUTOFF_HOUR_UTC", "20"))


def access_url() -> str:
    url = os.environ.get("SIMPLEFIN_ACCESS_URL")
    if not url:
        sys.exit("SIMPLEFIN_ACCESS_URL is not set")
    return url


def fetch_accounts(url: str) -> bytes:
    """GET {base}/accounts, pulling HTTP Basic creds out of the access URL."""
    parts = urlsplit(url)
    auth = (parts.username or "", parts.password or "")
    netloc = parts.hostname or ""
    if parts.port:
        netloc = f"{netloc}:{parts.port}"
    base = urlunsplit((parts.scheme, netloc, parts.path, "", "")).rstrip("/")
    start = datetime.now(timezone.utc) - timedelta(days=PULL_WINDOW_DAYS)
    params = {"start-date": int(start.timestamp())}
    resp = requests.get(f"{base}/accounts", auth=auth, params=params, timeout=60)
    resp.raise_for_status()
    return resp.content


def is_empty(raw: bytes) -> bool:
    try:
        return not json.loads(raw).get("accounts")
    except ValueError:
        return True


def day_prefix(now: datetime) -> tuple[str, str]:
    """Return (bucket, key prefix) for the given day, e.g. transactions/2026/06/30/."""
    bucket = os.environ.get("S3_BUCKET", "pfc-nfcu")
    prefix = (os.environ.get("S3_PREFIX") or "transactions").strip("/")
    return bucket, f"{prefix}/{now:%Y/%m/%d}/"


def stored_balance_dates(now: datetime) -> list[int]:
    """Balance-dates already captured today and yesterday (spans the day boundary)."""
    s3 = boto3.client("s3")
    out: list[int] = []
    for day in (now, now - timedelta(days=1)):
        bucket, prefix = day_prefix(day)
        for obj in s3.list_objects_v2(Bucket=bucket, Prefix=prefix).get("Contents", []):
            m = BD_KEY_RE.search(obj["Key"])
            if m:
                out.append(int(m.group(1)))
    return out


def max_balance_date(raw: bytes) -> int | None:
    """Newest balance-date across accounts, or None."""
    try:
        accounts = json.loads(raw).get("accounts") or []
    except ValueError:
        return None
    bds = [a["balance-date"] for a in accounts if a.get("balance-date")]
    return max(bds) if bds else None


def upload(raw: bytes, now: datetime, bd: int) -> str:
    bucket, prefix = day_prefix(now)
    key = f"{prefix}{now:%Y-%m-%dT%H%M%S}Z_bd{bd}.json"
    boto3.client("s3").put_object(
        Bucket=bucket, Key=key, Body=raw, ContentType="application/json"
    )
    return f"s3://{bucket}/{key}"


def main() -> None:
    now = datetime.now(timezone.utc)
    stored = stored_balance_dates(now)

    # Done for today once we've captured a refresh whose balance-date is dated
    # today: MX refreshes ~once/day, so there's nothing newer to wait for.
    if any(datetime.fromtimestamp(bd, timezone.utc).date() == now.date() for bd in stored):
        print("Today's refresh already captured; nothing to do.")
        return

    try:
        raw = fetch_accounts(access_url())
        if is_empty(raw):
            raise RuntimeError("SimpleFIN returned no accounts")
    except Exception as exc:
        # Stay quiet during the day's retries; only alert once the cutoff passes
        # with still no successful fetch. The next hourly run is the retry.
        if now.hour >= ALERT_CUTOFF_HOUR_UTC:
            sys.exit(f"No successful fetch by {ALERT_CUTOFF_HOUR_UTC}:00 UTC: {exc}")
        print(f"Fetch failed ({exc}); retrying next hour.")
        return

    # Fetch succeeded but the data may be unchanged since the last stored pull.
    # Only write (and thus stop) once balance-date actually advances.
    bd = max_balance_date(raw)
    last = max(stored) if stored else None
    if bd is not None and last is not None and bd <= last:
        print(f"No new refresh yet (balance-date {bd} <= stored {last}); retrying next hour.")
        return

    marker = bd if bd is not None else int(now.timestamp())
    print(f"Wrote {len(raw)} bytes to {upload(raw, now, marker)}")


if __name__ == "__main__":
    main()
