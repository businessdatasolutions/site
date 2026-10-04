#!/usr/bin/env bash
# Tests voor scripts/push-staging.sh. Pusht naar een lokale bare repo; geen netwerk.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUSH="$ROOT/scripts/push-staging.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# omhulde_site <map>: echte build met staging-omhulsel
omhulde_site() {
  "$ROOT/scripts/build.sh" "$1" >/dev/null
  "$ROOT/scripts/staging-envelope.sh" "$1" staging.example.nl >/dev/null
}

git init -q --bare -b main "$TMP/remote.git"
export STAGING_REMOTE="$TMP/remote.git"
unset DEPLOY_KEY

echo "push: omhulde site komt als één commit op main"
omhulde_site "$TMP/site"
if "$PUSH" "$TMP/site" >/dev/null 2>&1; then pass "eerste push slaagt"; else fail "eerste push faalde"; fi
if "$PUSH" "$TMP/site" >/dev/null 2>&1; then pass "tweede push slaagt"; else fail "tweede push faalde"; fi
n=$(git --git-dir="$TMP/remote.git" rev-list --count main 2>/dev/null || echo 0)
if [[ "$n" == "1" ]]; then pass "main heeft 1 commit"; else fail "main heeft $n commits, verwacht 1"; fi
git --git-dir="$TMP/remote.git" show main:CNAME > "$TMP/cname" 2>/dev/null
assert_file_equals "$TMP/cname" "staging.example.nl"
if git --git-dir="$TMP/remote.git" cat-file -e main:.nojekyll 2>/dev/null; then pass ".nojekyll meegepusht"; else fail ".nojekyll ontbreekt"; fi
if git --git-dir="$TMP/remote.git" cat-file -e main:.build-output 2>/dev/null; then fail ".build-output is meegepusht"; else pass ".build-output niet meegepusht"; fi
assert_absent "$TMP/site/.git"

echo "push: weigert een build zonder omhulsel"
"$ROOT/scripts/build.sh" "$TMP/kaal" >/dev/null
assert_fails "geen CNAME" "$PUSH" "$TMP/kaal"
omhulde_site "$TMP/half"
echo '<html><head></head><body>nieuw</body></html>' > "$TMP/half/nieuw.html"
assert_fails "pagina zonder noindex" "$PUSH" "$TMP/half"
n=$(git --git-dir="$TMP/remote.git" rev-list --count main 2>/dev/null || echo 0)
if [[ "$n" == "1" ]]; then pass "remote onaangeroerd"; else fail "remote gewijzigd ($n commits)"; fi

echo "push: ssh-remote zonder deploy key"
melding=$(STAGING_REMOTE="git@github.com:voorbeeld/bestaat-niet.git" DEPLOY_KEY="" "$PUSH" "$TMP/site" 2>&1)
status=$?
if [[ $status -ne 0 ]]; then pass "faalt terecht zonder sleutel"; else fail "slaagde zonder sleutel"; fi
if [[ "$melding" == *"STAGING_DEPLOY_KEY"* ]]; then pass "foutmelding noemt STAGING_DEPLOY_KEY"; else fail "onduidelijke foutmelding: $melding"; fi

echo "push: map bestaat niet"
assert_fails "map bestaat niet" "$PUSH" "$TMP/bestaat-niet"

finish
