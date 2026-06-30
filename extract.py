#!/usr/bin/env python3
"""Fetch raw account data from SimpleFIN and dump it verbatim to S3."""
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit, urlunsplit

import boto3
import requests

# Every run re-fetches a wide window so a missed/dropped run is backfilled by
# the next success. Dedup happens later in dbt, not here. 90 is SimpleFIN's
# max window; wide windows emit a harmless "exceeds recommended range" warning
# in `errors` that does not reduce data or trip the empty-pull alert.
PULL_WINDOW_DAYS = int(os.environ.get("PULL_WINDOW_DAYS", "90"))


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


def upload(raw: bytes) -> str:
    bucket = os.environ.get("S3_BUCKET", "pfc-nfcu")
    prefix = (os.environ.get("S3_PREFIX") or "transactions").strip("/")
    now = datetime.now(timezone.utc)
    key = f"{prefix}/{now:%Y/%m/%d}/{now:%Y-%m-%dT%H%M%S}Z.json"
    boto3.client("s3").put_object(
        Bucket=bucket, Key=key, Body=raw, ContentType="application/json"
    )
    return f"s3://{bucket}/{key}"


def main() -> None:
    raw = fetch_accounts(access_url())
    if is_empty(raw):
        sys.exit("SimpleFIN returned no accounts; failing run to trigger alert")
    print(f"Wrote {len(raw)} bytes to {upload(raw)}")


if __name__ == "__main__":
    main()
