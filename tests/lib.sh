# Gedeelde testhulpjes. Gebruik in een test: source "$(dirname "$0")/lib.sh"
FAILS=0

pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

assert_exists() { if [[ -e "$1" ]]; then pass "bestaat: $1"; else fail "ontbreekt: $1"; fi; }
assert_absent() { if [[ ! -e "$1" ]]; then pass "afwezig: $1"; else fail "had niet mogen bestaan: $1"; fi; }

assert_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then pass "${1##*/} bevat '$2'"; else fail "${1##*/} mist '$2'"; fi
}
assert_not_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then fail "${1##*/} bevat onterecht '$2'"; else pass "${1##*/} bevat geen '$2'"; fi
}
assert_count() {
  local n
  n=$(grep -oF -- "$2" "$1" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$n" == "$3" ]]; then pass "${1##*/}: '$2' ${3}x"; else fail "${1##*/}: '$2' ${n}x, verwacht $3"; fi
}
assert_file_equals() {
  local inhoud
  inhoud="$(cat "$1" 2>/dev/null)"
  if [[ "$inhoud" == "$2" ]]; then pass "${1##*/} = '$2'"; else fail "${1##*/} = '$inhoud', verwacht '$2'"; fi
}
# assert_fails <omschrijving> <commando…>: het commando moet met exit ≠ 0 eindigen
assert_fails() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "had moeten falen: $desc"; else pass "faalt terecht: $desc"; fi
}

finish() {
  if [[ $FAILS -gt 0 ]]; then echo "  $FAILS controle(s) mislukt"; exit 1; fi
}
