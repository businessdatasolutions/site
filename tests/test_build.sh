#!/usr/bin/env bash
# Tests voor scripts/build.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "build: publiceert precies de allowlist"
if "$ROOT/scripts/build.sh" "$TMP/out" >/dev/null; then pass "build.sh slaagt"; else fail "build.sh faalde"; fi
assert_exists "$TMP/out/index.html"
assert_exists "$TMP/out/styles.css"
assert_exists "$TMP/out/blog/index.html"
assert_exists "$TMP/out/blog/branches-not-time/index.html"
assert_exists "$TMP/out/blog/three-model-calls/index.html"
assert_exists "$TMP/out/images/logo.png"
for x in README.md CNAME docs scripts tests .github .gitignore; do
  assert_absent "$TMP/out/$x"
done

echo "build: een tweede build begint schoon"
touch "$TMP/out/oud-bestand.html"
"$ROOT/scripts/build.sh" "$TMP/out" >/dev/null
assert_absent "$TMP/out/oud-bestand.html"
assert_exists "$TMP/out/index.html"

echo "build: raakt geen map aan die het niet zelf gemaakt heeft"
mkdir -p "$TMP/vreemd" && echo "belangrijk" > "$TMP/vreemd/notities.txt"
assert_fails "bestaande vreemde map" "$ROOT/scripts/build.sh" "$TMP/vreemd"
assert_exists "$TMP/vreemd/notities.txt"
echo "geen map" > "$TMP/een-bestand"
assert_fails "uitvoerpad is een bestand" "$ROOT/scripts/build.sh" "$TMP/een-bestand"
assert_exists "$TMP/een-bestand"

echo "build: faalt als een allowlist-item ontbreekt"
mkdir -p "$TMP/repo/scripts"
cp "$ROOT/scripts/build.sh" "$TMP/repo/scripts/"
cp -R "$ROOT/index.html" "$ROOT/blog" "$ROOT/images" "$TMP/repo/"   # styles.css ontbreekt bewust
assert_fails "styles.css ontbreekt" "$TMP/repo/scripts/build.sh" "$TMP/out2"
assert_absent "$TMP/out2"

finish
