#!/usr/bin/env bash
#
# run.sh — "run for real": rebuild + serve the Evidence dashboard on YOUR real
# bank data, undoing any persona override that persona.sh left behind.
#
# The dashboard's active config lives in dashboard/.env.local (git-ignored).
# persona.sh writes persona values there; this restores your real values from
# dashboard/.env.real (also git-ignored, never committed) so the page shows your
# real name/address and reads your real S3 data_root. If .env.real is absent it
# seeds .env.local from the committed dashboard/.env.example template — Evidence
# only auto-loads .env/.env.local, never *.example, so a bare "fall back to the
# committed defaults" would leave ${data_root} unresolved and the build empty.
#
# Chaining with && is intentional: if any step fails, the rest don't run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$ROOT/dashboard/.env.real" ]; then
  cp "$ROOT/dashboard/.env.real" "$ROOT/dashboard/.env.local"
  echo "run: restored real dashboard config from dashboard/.env.real"
else
  cp "$ROOT/dashboard/.env.example" "$ROOT/dashboard/.env.local"
  echo "run: no dashboard/.env.real found — seeded .env.local from committed dashboard/.env.example defaults"
  echo "run: (create dashboard/.env.real with your real EVIDENCE_VAR__* values to show them)"
fi

cd "$ROOT/dbt_code" && uv run dbt build \
  && cd "$ROOT/dashboard" && npm run sources && npm run dev
