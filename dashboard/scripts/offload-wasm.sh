#!/usr/bin/env bash
# Move the oversized DuckDB WASM engine files out of the Cloudflare Pages upload
# and rewrite Evidence's references to point at an R2 (or any) public CDN base URL.
#
# Why: Cloudflare Pages rejects any single file >25 MiB, and every DuckDB WASM
# variant is 33-38 MiB. The WASM is a public, non-sensitive engine binary, so it
# can be served from R2 instead. Only the guarded parquet data stays on Pages.
#
# Usage:  WASM_CDN_BASE="https://cdn.example.net" ./scripts/offload-wasm.sh [build_dir]
#   WASM_CDN_BASE  – public base URL where the wasm files will be served (no trailing slash)
#   build_dir      – Evidence build output (default: build)
#
# Effect:
#   * copies build/_app/immutable/assets/duckdb-*.wasm into build/_wasm_offload/ (for you to upload to R2)
#   * rewrites the "/_app/immutable/assets/duckdb-*.wasm" literal in the JS chunks to "$WASM_CDN_BASE/duckdb-*.wasm"
#   * deletes the wasm files from the Pages upload tree
set -euo pipefail

BUILD_DIR="${1:-build}"
: "${WASM_CDN_BASE:?set WASM_CDN_BASE to the public base URL, e.g. https://cdn.example.net}"
WASM_CDN_BASE="${WASM_CDN_BASE%/}"   # strip any trailing slash

ASSET_DIR="$BUILD_DIR/_app/immutable/assets"
# stage OUTSIDE the build tree, or `pages deploy build` would re-upload these and
# hit the very 25 MiB limit we're working around.
OFFLOAD_DIR="${WASM_OFFLOAD_DIR:-${BUILD_DIR%/}-wasm-offload}"
rm -rf "$OFFLOAD_DIR"
mkdir -p "$OFFLOAD_DIR"

shopt -s nullglob
wasm_files=("$ASSET_DIR"/duckdb-*.wasm)
if [ ${#wasm_files[@]} -eq 0 ]; then
  echo "no duckdb-*.wasm found under $ASSET_DIR — nothing to offload (did the build run?)" >&2
  exit 1
fi

for wasm in "${wasm_files[@]}"; do
  fname="$(basename "$wasm")"
  old="/_app/immutable/assets/$fname"
  new="$WASM_CDN_BASE/$fname"

  # rewrite every JS chunk that inlines this asset path
  # (pattern starts with "/", so no need for "--"; keep --include so we only scan JS)
  hits=$(grep -rl --include="*.js" "$old" "$BUILD_DIR" || true)
  if [ -z "$hits" ]; then
    echo "WARNING: no JS reference found for $fname (Evidence internals may have changed)" >&2
  else
    while IFS= read -r js; do
      # exact-string replace; paths contain only [A-Za-z0-9._/-] so sed delimiter | is safe
      sed -i "s|$old|$new|g" "$js"
      echo "rewrote reference in ${js#$BUILD_DIR/}  ->  $new"
    done <<< "$hits"
  fi

  # stage for R2 upload, then remove from the Pages tree
  cp "$wasm" "$OFFLOAD_DIR/$fname"
  rm "$wasm"
  echo "offloaded $fname ($(du -h "$OFFLOAD_DIR/$fname" | cut -f1))"
done

echo
echo "staged for R2 upload in: $OFFLOAD_DIR"
echo "remaining files >25MiB in $BUILD_DIR:"
find "$BUILD_DIR" -type f -size +25M -exec ls -lh {} \; || true
echo "(none listed above = safe to deploy to Pages)"
