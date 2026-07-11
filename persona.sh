#!/usr/bin/env bash
#
# persona.sh — run the demo pipeline against a fictional persona instead of your
# real bank data. Everything a persona touches lives under a per-persona S3 root
# (s3://<bucket>/<demo-prefix>/<slug>/), so your real pipeline is never touched.
#
#   ./persona.sh list                 # personas you can run
#   ./persona.sh new <slug> [--from <existing>]   # scaffold a new persona to edit
#   ./persona.sh <slug> [--no-serve]  # generate -> upload -> dbt -> dashboard
#   ./persona.sh reset <slug> [--yes] # wipe the persona's S3 + local data, then rebuild
#   ./persona.sh check <slug>         # validate the persona's YAML without running
#
# Overridable env: PFC_BUCKET (default pfc-nfcu), PFC_DEMO_PREFIX (default demo).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSONAS_DIR="$ROOT/synthetic/personas"
BUCKET="${PFC_BUCKET:-pfc-nfcu}"
DEMO_PREFIX="${PFC_DEMO_PREFIX:-demo}"

die() { echo "error: $*" >&2; exit 1; }

available() { ls -1 "$PERSONAS_DIR" 2>/dev/null | tr '\n' ' '; }

cmd_list() {
  echo "personas under $PERSONAS_DIR:"
  for d in "$PERSONAS_DIR"/*/; do
    [ -d "$d" ] || continue
    printf '  %s\n' "$(basename "$d")"
  done
}

cmd_new() {
  local slug="${1:-}" from="jordan-rivera"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="${2:?--from needs a value}"; shift 2 ;;
      *) die "unknown option for 'new': $1" ;;
    esac
  done
  [ -n "$slug" ] || die "usage: ./persona.sh new <slug> [--from <existing>]"
  [ -d "$PERSONAS_DIR/$from" ] || die "no template persona '$from' (have: $(available))"
  local dest="$PERSONAS_DIR/$slug"
  [ -e "$dest" ] && die "persona '$slug' already exists at $dest"
  cp -r "$PERSONAS_DIR/$from" "$dest"
  echo "Scaffolded '$slug' from '$from'."
  echo "Now edit the identity so it's nobody real, and change 'seed:' for a fresh draw:"
  echo "  $dest/persona.yaml"
  echo "  $dest/merchants.yaml"
  echo "Then run it with:  ./persona.sh $slug"
}

cmd_check() {
  local slug="${1:-}"
  [ -n "$slug" ] || die "usage: ./persona.sh check <slug>"
  [ -d "$PERSONAS_DIR/$slug" ] || die "no persona '$slug' (have: $(available))"
  uv run python "$ROOT/synthetic/validate.py" --persona "$slug"
}

cmd_run() {
  local slug="${1:-}"; shift || true
  local serve=1 reset=0 assume_yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-serve) serve=0; shift ;;
      --reset) reset=1; shift ;;
      --yes|-y) assume_yes=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -n "$slug" ] || die "usage: ./persona.sh <slug> [--no-serve]"
  [ -d "$PERSONAS_DIR/$slug" ] || die "no persona '$slug' (have: $(available))"

  local data_root="s3://$BUCKET/$DEMO_PREFIX/$slug"
  local out="$ROOT/synthetic/out/$slug"
  local seed_local="$out/seed_merchant_category_regex_mapping.csv"
  local seed_s3="$data_root/stage/seed_merchant_category_regex_mapping.csv"

  echo "== persona '$slug' -> $data_root"
  command -v aws >/dev/null || die "aws CLI not found"
  aws sts get-caller-identity >/dev/null 2>&1 || die "no usable AWS credentials (same chain as the real pipeline)"

  # Validate BEFORE any wipe so a broken persona never destroys good S3 data.
  echo "== [check] validate persona YAML"
  uv run python "$ROOT/synthetic/validate.py" --persona "$slug"

  if [ "$reset" -eq 1 ]; then
    # Full reset: the normal run only reconciles transactions/ (sync --delete);
    # dbt-written stage/ and dashboard_mart/ can go stale. Wiping the whole
    # persona subtree (always .../$DEMO_PREFIX/$slug/, never the bucket root or
    # your real data) is the only way to guarantee a clean slate.
    [ -n "$slug" ] || die "reset needs a persona slug"
    if [ "$assume_yes" -eq 0 ]; then
      echo   "== [reset] this DELETES everything for '$slug':"
      printf '     S3:    %s/  (recursive)\n' "$data_root"
      printf '     local: %s/\n' "$out"
      read -r -p "     proceed? [y/N] " ans || true
      case "${ans:-}" in y|Y|yes|YES) ;; *) die "reset aborted" ;; esac
    fi
    echo "== [reset] wiping S3 subtree + local out + dashboard Evidence cache"
    aws s3 rm "$data_root/" --recursive
    rm -rf "$out" "$ROOT/dashboard/.evidence"
  fi

  echo "== [1/5] generate + verify"
  uv run python "$ROOT/synthetic/generate.py" --persona "$slug"
  uv run python "$ROOT/synthetic/verify.py" --persona "$slug"

  echo "== [2/5] upload transactions + regex seed to S3"
  aws s3 sync "$out/transactions/" "$data_root/transactions/" --delete
  aws s3 cp "$seed_local" "$seed_s3"

  echo "== [3/5] dbt build on the persona's data"
  ( cd "$ROOT/dbt_code" && uv run dbt build \
      --vars "{data_root: '$data_root', regex_seed_csv: '$seed_s3'}" )

  echo "== [4/5] point the dashboard at the persona"
  {
    printf 'EVIDENCE_VAR__data_root=%s\n' "$data_root"
    uv run python "$ROOT/synthetic/persona_meta.py" --persona "$slug" --env
  } > "$ROOT/dashboard/.env.local"

  if [ "$serve" -eq 0 ]; then
    echo "== [5/5] skipped (--no-serve). Data is live at $data_root."
    echo "   Start the demo later with: (cd dashboard && npm run sources && npm run dev)"
    return 0
  fi
  echo "== [5/5] build sources + serve dashboard on localhost (Ctrl-C to stop)"
  cd "$ROOT/dashboard"
  [ -d node_modules ] || npm install
  npm run sources
  npm run dev
}

main() {
  local verb="${1:-}"
  case "$verb" in
    ""|-h|--help) grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | tail -n +2 | head -n 11 ;;
    list) cmd_list ;;
    new)  shift; cmd_new "$@" ;;
    check) shift; cmd_check "$@" ;;
    reset) shift; cmd_run "$@" --reset ;;
    *)    cmd_run "$@" ;;
  esac
}

main "$@"
