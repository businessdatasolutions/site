#!/usr/bin/env bash
# Draait alle tests (tests/test_*.sh). Exit 0 als alles slaagt.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
for t in tests/test_*.sh; do
  echo "── $t"
  bash "$t" || status=1
done
if [[ $status -eq 0 ]]; then echo "Alle tests geslaagd."; else echo "Er zijn tests mislukt."; fi
exit $status
