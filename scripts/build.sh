#!/usr/bin/env bash
# Bouwt de publiceerbare site in een uitvoermap (standaard _site/).
#
# Allowlist: alleen wat in PUBLIC staat wordt gepubliceerd. Een nieuw publiek
# bestand of een nieuwe publieke map moet hier expliciet bij; zo komt een intern
# bestand (spec, script, schets) nooit per ongeluk online.
#
# Gebruik: scripts/build.sh [uitvoermap]
set -euo pipefail

PUBLIC=(index.html styles.css blog images)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-_site}"
MARKER=".build-output"   # build.sh wist alleen mappen waarin dit bestand staat

for item in "${PUBLIC[@]}"; do
  if [[ ! -e "$ROOT/$item" ]]; then
    echo "build.sh: '$item' staat in PUBLIC maar ontbreekt in de repo" >&2
    exit 1
  fi
done

if [[ -e "$OUT" ]]; then
  if [[ ! -d "$OUT" ]] || { [[ -n "$(ls -A "$OUT")" ]] && [[ ! -f "$OUT/$MARKER" ]]; }; then
    echo "build.sh: '$OUT' bestaat al en is niet door build.sh gemaakt; ik overschrijf het niet" >&2
    exit 2
  fi
  rm -rf "$OUT"
fi

mkdir -p "$OUT"
touch "$OUT/$MARKER"
for item in "${PUBLIC[@]}"; do
  cp -R "$ROOT/$item" "$OUT/"
done

echo "build.sh: $(find "$OUT" -type f ! -name "$MARKER" | wc -l | tr -d ' ') bestanden in $OUT"
