#!/usr/bin/env bash
# Bewaakt de belangrijkste afspraken in de workflow (spec §6). Tekstcontroles:
# grof, maar ze vangen het per ongeluk weghalen van een veiligheidsregel.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
WF="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/deploy.yml"

echo "workflow: afspraken uit de spec"
assert_exists "$WF"
assert_contains "$WF" "retention-days: 30"                        # goedkeuring mag tot 30 dagen wachten
assert_contains "$WF" "if: github.ref == 'refs/heads/master'"     # alleen master naar prod
assert_contains "$WF" "if: github.event_name != 'pull_request'"   # PR's deployen niet
assert_count "$WF" "name: github-pages" 2                         # artifactnaam + omgeving (prod achter de reviewer)
assert_contains "$WF" "cancel-in-progress: false"                 # prod-deploy nooit afbreken
assert_contains "$WF" "  contents: read"                          # standaard alleen lezen
assert_count "$WF" "secrets.STAGING_DEPLOY_KEY" 1                 # sleutel alleen in deploy-staging
assert_count "$WF" "pages: write" 1                               # alleen de prod-job
# Externe action draait vóór de artifact-upload en kan dus de prod-build raken: vastpinnen op een commit.
if grep -qE 'uses: lycheeverse/lychee-action@[0-9a-f]{40}( |$)' "$WF"; then
  pass "lychee-action vastgepind op commit-SHA"
else
  fail "lychee-action niet vastgepind op commit-SHA"
fi
assert_not_contains "$WF" "ci/pipeline"                           # tijdelijke trigger is weg (spec §8 stap 6)

finish
