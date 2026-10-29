#!/bin/sh
# Копия scripts/fork/smoke.sh из curtisjackson/it-tools: обновлять вместе с ним.
# Использование: sh tests/smoke.sh http://192.168.1.11:9449/
# Smoke test of a running image of this fork, over HTTP only, so it works against a local container in CI as well
# as against the server.
#
#   sh scripts/fork/smoke.sh http://127.0.0.1:8080/            # image served from /
#   sh scripts/fork/smoke.sh http://127.0.0.1:8080/it-tools/   # image run with BASE_URL=/it-tools/
#
# It checks the page and its headers (COOP/COEP, without which the WebAssembly tools stop working), the rewritten
# <base href>, a deep link, precompressed assets, the chunks of some tools of this fork, and the ffmpeg core.
set -eu

url="${1:?usage: smoke.sh <url of the app, ending with />}"
case "$url" in */) ;; *) url="$url/" ;; esac
base_path="/${url#*://*/}"

# Tools of this fork whose chunks must be in the bundle.
TOOLS="video-trim text-reverse csv-transpose pdf-rotate png-compressor"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

ok() { printf 'ok    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

# fetch <path> [curl options...]: body to $tmp/body, headers to $tmp/headers, prints the status code.
fetch() {
  path="$1"
  shift
  : > "$tmp/body"
  : > "$tmp/headers"
  curl -sS -o "$tmp/body" -D "$tmp/headers" -w '%{http_code}' "$@" "$url$path" || true
}

header() { grep -i "^$1:" "$tmp/headers" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }

expect() {
  name="$1" path="$2" type="$3"
  shift 3
  status="$(fetch "$path" "$@")"
  content_type="$(header Content-Type)"
  case "$status:$content_type" in
    200:"$type"*) ok "$name ($path)" ;;
    *) fail "$name ($path): HTTP $status, $content_type" ;;
  esac
}

expect 'page' '' 'text/html'
[ "$(header Cross-Origin-Opener-Policy)" = 'same-origin' ] && ok 'COOP header' || fail 'COOP header'
[ "$(header Cross-Origin-Embedder-Policy)" = 'require-corp' ] && ok 'COEP header' || fail 'COEP header'
grep -q "<base href=\"$base_path\">" "$tmp/body" && ok "base href $base_path" || fail "base href $base_path"
main="$(grep -o 'assets/index-[A-Za-z0-9_-]*\.js' "$tmp/body" | head -1)"

expect 'deep link' 'video-trim' 'text/html'
# nginx's mime.types has no type for .webmanifest; browsers read the manifest anyway.
status="$(fetch 'manifest.webmanifest')"
[ "$status" = 200 ] && grep -q '"start_url"' "$tmp/body" && ok 'web manifest' || fail "web manifest: HTTP $status"
expect 'service worker' 'sw.js' 'application/javascript'

if [ -z "$main" ]; then
  fail 'main chunk: not found in the page'
else
  expect 'main chunk' "$main" 'application/javascript'
  store="$(grep -o 'tools\.store-[A-Za-z0-9_-]*\.js' "$tmp/body" | head -1)"
  status="$(fetch "$main" -H 'Accept-Encoding: gzip')"
  [ "$(header Content-Encoding)" = 'gzip' ] && ok 'precompressed asset' || fail 'precompressed asset'
fi

if [ -z "${store:-}" ]; then
  fail 'tool list chunk: not found in the main chunk'
else
  expect 'tool list chunk' "assets/$store" 'application/javascript'
  cp "$tmp/body" "$tmp/store"
  for tool in $TOOLS; do
    chunk="$(grep -o "\"\./$tool-[A-Za-z0-9_-]*\.js\"" "$tmp/store" | head -1 | tr -d '"' | sed 's|^\./||')"
    if [ -n "$chunk" ]; then
      expect "tool $tool" "assets/$chunk" 'application/javascript'
    else
      fail "tool $tool: no chunk"
    fi
  done
  core="$(grep -o 'ffmpeg-core-[A-Za-z0-9_-]*\.js' "$tmp/store" | head -1)"
  if [ -n "$core" ]; then
    expect 'ffmpeg core' "assets/$core" 'application/javascript'
    wasm="$(grep -o 'ffmpeg-core-[A-Za-z0-9_-]*\.wasm' "$tmp/body" | head -1)"
    [ -n "$wasm" ] && expect 'ffmpeg core wasm' "assets/$wasm" 'application/wasm' || fail 'ffmpeg core wasm: not found'
  else
    fail 'ffmpeg core: not found in the tool list chunk'
  fi
fi

if [ "$failures" -gt 0 ]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
echo 'all checks passed'
