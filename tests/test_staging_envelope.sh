#!/usr/bin/env bash
# Tests voor scripts/staging-envelope.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENVELOPE="$ROOT/scripts/staging-envelope.sh"
HOST="staging.example.nl"
META='<meta name="robots" content="noindex, nofollow">'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fixture <map>: kleine site met een analytics-blok op de homepage en een subpagina
fixture() {
  mkdir -p "$1/sub"
  cat > "$1/index.html" <<'HTML'
<html>
  <head>
    <title>Home</title>
    <!-- analytics:start -->
    <script src="https://static.hotjar.com/c/hotjar-1.js"></script>
    <!-- analytics:end -->
  </head>
  <body><h1>Hallo</h1></body>
</html>
HTML
  cat > "$1/sub/pagina.html" <<'HTML'
<html><HEAD><title>Sub</title></HEAD><body><p>Sub</p></body></html>
HTML
}

echo "omhulsel: normale site"
fixture "$TMP/a"
if "$ENVELOPE" "$TMP/a" "$HOST" >/dev/null; then pass "script slaagt"; else fail "script faalde"; fi
assert_count "$TMP/a/index.html" "$META" 1
assert_count "$TMP/a/sub/pagina.html" "$META" 1
assert_not_contains "$TMP/a/index.html" "hotjar"
assert_not_contains "$TMP/a/index.html" "analytics:"
assert_contains "$TMP/a/index.html" "<h1>Hallo</h1>"
assert_file_equals "$TMP/a/CNAME" "$HOST"
assert_exists "$TMP/a/.nojekyll"

echo "omhulsel: twee keer draaien geeft geen dubbele meta"
"$ENVELOPE" "$TMP/a" "$HOST" >/dev/null
assert_count "$TMP/a/index.html" "$META" 1
assert_count "$TMP/a/sub/pagina.html" "$META" 1

echo "omhulsel: markeringen midden in een regel"
mkdir -p "$TMP/inline"
echo '<html><head><!-- analytics:start --><script src="https://static.hotjar.com/x.js"></script><!-- analytics:end --></head><body></body></html>' > "$TMP/inline/index.html"
"$ENVELOPE" "$TMP/inline" "$HOST" >/dev/null || fail "script faalde op inline markeringen"
assert_not_contains "$TMP/inline/index.html" "hotjar"
assert_count "$TMP/inline/index.html" "$META" 1

echo "omhulsel: pagina zonder </head> laat alles onaangeroerd"
fixture "$TMP/b"
echo "<html><body>kapot</body></html>" > "$TMP/b/kapot.html"
assert_fails "pagina zonder </head>" "$ENVELOPE" "$TMP/b" "$HOST"
assert_count "$TMP/b/index.html" "$META" 0
assert_contains "$TMP/b/index.html" "hotjar"
assert_absent "$TMP/b/CNAME"

echo "omhulsel: markering zonder partner"
fixture "$TMP/c"
echo "<html><head><!-- analytics:start --></head><body></body></html>" > "$TMP/c/half.html"
assert_fails "analytics:start zonder end" "$ENVELOPE" "$TMP/c" "$HOST"
fixture "$TMP/d"
echo "<html><head><!-- analytics:end --></head><body></body></html>" > "$TMP/d/half.html"
assert_fails "analytics:end zonder start" "$ENVELOPE" "$TMP/d" "$HOST"

echo "omhulsel: leeg html-bestand"
fixture "$TMP/f"
: > "$TMP/f/leeg.html"
assert_fails "leeg html-bestand" "$ENVELOPE" "$TMP/f" "$HOST"
assert_count "$TMP/f/index.html" "$META" 0

echo "omhulsel: pagina die niet bijgewerkt kan worden"
if [[ $(id -u) -eq 0 ]]; then
  pass "overgeslagen als root (bestandsrechten gelden dan niet)"
else
  fixture "$TMP/g"
  chmod 555 "$TMP/g/sub"
  assert_fails "onschrijfbare submap" "$ENVELOPE" "$TMP/g" "$HOST"
  chmod 755 "$TMP/g/sub"
  assert_absent "$TMP/g/CNAME"
fi

echo "omhulsel: ongeldige argumenten"
fixture "$TMP/e"
assert_fails "host met https://" "$ENVELOPE" "$TMP/e" "https://$HOST"
assert_fails "host met pad" "$ENVELOPE" "$TMP/e" "$HOST/"
assert_fails "lege host" "$ENVELOPE" "$TMP/e" ""
assert_fails "map bestaat niet" "$ENVELOPE" "$TMP/bestaat-niet" "$HOST"
mkdir -p "$TMP/leeg"
assert_fails "map zonder html" "$ENVELOPE" "$TMP/leeg" "$HOST"
assert_count "$TMP/e/index.html" "$META" 0

echo "omhulsel: de echte site"
"$ROOT/scripts/build.sh" "$TMP/prod" >/dev/null
"$ROOT/scripts/build.sh" "$TMP/staging" >/dev/null
"$ENVELOPE" "$TMP/staging" "$HOST" >/dev/null || fail "omhulsel faalde op de echte site"
assert_contains "$TMP/prod/index.html" "static.hotjar.com"   # prod houdt analytics
assert_count "$TMP/prod/index.html" "$META" 0                # prod blijft indexeerbaar
assert_not_contains "$TMP/staging/index.html" "hotjar"
for f in index.html blog/index.html blog/branches-not-time/index.html blog/three-model-calls/index.html; do
  assert_count "$TMP/staging/$f" "$META" 1
done

finish
