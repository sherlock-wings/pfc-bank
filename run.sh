#!/usr/bin/env bash
#
# run.sh — "run for real": rebuild + serve the Evidence dashboard on YOUR real
# bank data, undoing any persona override that persona.sh left behind.
#
# The dashboard's active config lives in dashboard/.env.local (git-ignored).
# persona.sh writes persona values there; this restores your real values from
# dashboard/.env.real (also git-ignored, never committed) so the page shows your
# real name/address and reads your real S3 data_root. If .env.real is absent it
# just clears .env.local, falling back to the committed (placeholder) .env.
#
# Chaining with && is intentional: if any step fails, the rest don't run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$ROOT/dashboard/.env.real" ]; then
  cp "$ROOT/dashboard/.env.real" "$ROOT/dashboard/.env.local"
  echo "run: restored real dashboard config from dashboard/.env.real"
else
  rm -f "$ROOT/dashboard/.env.local"
  echo "run: no dashboard/.env.real found — cleared .env.local, using committed .env defaults"
  echo "run: (create dashboard/.env.real with your real EVIDENCE_VAR__* values to show them)"
fi

cd "$ROOT/dbt_code" && uv run dbt build \
  && cd "$ROOT/dashboard" && npm run sources && npm run dev
