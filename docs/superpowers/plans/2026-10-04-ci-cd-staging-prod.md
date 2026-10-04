# CI/CD met staging en productie — implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elke wijziging aan `businessdatasolutions/site` gaat automatisch naar `staging.businessdatasolutions.nl` en pas na goedkeuring van Witek, met exact dezelfde build, naar `www.businessdatasolutions.nl`.

**Architecture:** Eén GitHub Actions-workflow (`deploy.yml`) met drie jobs: `build` (tests, build via allowlist, linkcheck, artifact), `deploy-staging` (staging-omhulsel + force-push naar de aparte repo `site-staging`, gehost via Pages) en `deploy-production` (`actions/deploy-pages` in de omgeving `github-pages`, met Witek als verplichte reviewer). De logica zit in drie kleine bash-scripts met eigen tests; de workflow roept ze alleen aan.

**Tech Stack:** bash + perl (draait op macOS én Ubuntu), GitHub Actions, GitHub Pages, lychee (linkcheck), `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-10-04-ci-cd-staging-prod-design.md`

## Global Constraints

- Alle werk op branch `ci/pipeline` tot Task 7. Tot dan mag de live site (`www.businessdatasolutions.nl`) niet veranderen.
- Scripts draaien op macOS (BSD-tools) én Ubuntu (GNU-tools): geen `sed -i`; in-place bewerken met `perl -0777 -pi -e`; bestandslijsten met `find … -print0`.
- Lokale bash is 3.2 (macOS `/bin/bash`): geen bash-4-features (`mapfile`, associatieve arrays, `${var,,}`) en geen `"${arr[@]}"` op een mogelijk lege array onder `set -u`.
- Taal: commentaar, foutmeldingen, testuitvoer, README en commitberichten in het Nederlands. Elk commitbericht eindigt met `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Staging-host: `staging.businessdatasolutions.nl`. Prod-host: `www.businessdatasolutions.nl`. Staging-repo: `businessdatasolutions/site-staging`.
- Allowlist van publieke bestanden: `index.html styles.css blog images`.
- Noindex-meta, letterlijk: `<meta name="robots" content="noindex, nofollow">`.
- Analytics-markeringen, letterlijk: `<!-- analytics:start -->` en `<!-- analytics:end -->`.
- Action-versies: `actions/checkout@v7`, `actions/upload-pages-artifact@v5` (met `retention-days: 30`), `actions/download-artifact@v8`, `actions/deploy-pages@v5`, `lycheeverse/lychee-action@e7477775783ea5526144ba13e8db5eec57747ce8 # v2.9.0` (externe action, vastgepind op commit; installeert lychee v0.24.2).
- Workflowrechten: standaard `contents: read`; alleen `deploy-production` krijgt `pages: write` en `id-token: write`.
- GitHub-gebruiker van Witek: `witusj`, id `5702329`.
- **Keur nooit zelf een productie-deploy goed namens Witek.** Goedkeuren is zijn handeling.
- Stappen met een **STOP** vereisen een expliciet akkoord van Witek voordat je verdergaat.

## Review Focus

1. **Goedkeuring later dan één dag.** `upload-pages-artifact` bewaart standaard 1 dag; daarna mislukt de prod-deploy. Verwacht: goedkeuren tot 30 dagen later werkt. → `tests/test_workflow.sh` controleert `retention-days: 30` (Task 4).
2. **Een build zonder omhulsel komt op staging** (bijv. als iemand de omhulsel-stap uit de workflow haalt): staging zou indexeerbaar zijn en Hotjar laden. Verwacht: push weigert. → `tests/test_push_staging.sh`, "weigert een build zonder omhulsel" (Task 3).
3. **Het secret `STAGING_DEPLOY_KEY` ontbreekt of is leeg.** Verwacht: een foutmelding die het secret bij naam noemt, geen cryptische ssh-fout. → `tests/test_push_staging.sh`, "ssh-remote zonder deploy key" (Task 3).
4. **Externe links, `mailto:`/`tel:` en `href="#"` in de offline linkcheck.** Verwacht: die laten de check niet falen; een kapotte interne link, een kapot anker of een ontbrekende afbeelding wel. → lokale lychee-run in beide richtingen (Task 4, stap 5–6).
5. **Twee runs wachten tegelijk op goedkeuring** (twee pushes kort na elkaar). Verwacht: duidelijk welke live gaat. → observatie in Task 8, stap 3, vastgelegd in de README.

---

## Voorbereiding (eenmalig per sessie)

```bash
cd ~/Projects/site
git switch ci/pipeline
SCRATCH="$(mktemp -d)"   # tijdelijke bestanden; nooit in de repo
```

---

### Task 1: Testhulpjes en `build.sh`

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/run.sh`
- Create: `tests/test_build.sh`
- Create: `scripts/build.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: niets.
- Produces:
  - `scripts/build.sh [uitvoermap]` — standaard `_site`. Exit 0 bij succes; exit 1 als een allowlist-item ontbreekt; exit 2 als de uitvoermap bestaat en niet door `build.sh` is gemaakt. Zet een verborgen bestand `.build-output` in de uitvoermap.
  - `tests/lib.sh` met: `pass`, `fail`, `assert_exists <pad>`, `assert_absent <pad>`, `assert_contains <bestand> <tekst>`, `assert_not_contains <bestand> <tekst>`, `assert_count <bestand> <tekst> <n>`, `assert_file_equals <bestand> <verwacht>`, `assert_fails <omschrijving> <commando…>`, `finish`.
  - `tests/run.sh` — draait elk `tests/test_*.sh`; exit 0 als alles slaagt.

- [ ] **Step 1: Schrijf de testhulpjes en de runner**

`tests/lib.sh`:

```bash
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
```

`tests/run.sh`:

```bash
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
```

- [ ] **Step 2: Schrijf de falende test voor `build.sh`**

`tests/test_build.sh`:

```bash
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
```

- [ ] **Step 3: Draai de tests en zie ze falen**

Run: `chmod +x tests/run.sh && bash tests/run.sh`
Expected: FAIL. `test_build.sh` meldt onder meer `✗ build.sh faalde` en `✗ ontbreekt: …/out/index.html`; de laatste regel is `Er zijn tests mislukt.`

- [ ] **Step 4: Schrijf `build.sh` en `.gitignore`**

`scripts/build.sh`:

```bash
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
```

`.gitignore`:

```
_site/
```

- [ ] **Step 5: Draai de tests en zie ze slagen**

Run: `chmod +x scripts/build.sh && bash tests/run.sh`
Expected: PASS. Alle regels in `test_build.sh` beginnen met `✓`; laatste regel `Alle tests geslaagd.`

Run ook: `scripts/build.sh && ls -A _site`
Expected: `.build-output  blog  images  index.html  styles.css`

- [ ] **Step 6: Commit**

```bash
git add .gitignore tests/lib.sh tests/run.sh tests/test_build.sh scripts/build.sh
git commit -F - <<'EOF'
feat(ci): build.sh met allowlist en testhulpjes

build.sh kopieert alleen index.html, styles.css, blog/ en images/ naar de
uitvoermap en wist nooit een map die het niet zelf gemaakt heeft.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Staging-omhulsel en analytics-markeringen

**Files:**
- Create: `tests/test_staging_envelope.sh`
- Create: `scripts/staging-envelope.sh`
- Modify: `index.html:19-34` (markeringen rond het Hotjar-blok)

**Interfaces:**
- Consumes: `scripts/build.sh [uitvoermap]` (Task 1); testhulpjes uit `tests/lib.sh` (Task 1).
- Produces: `scripts/staging-envelope.sh <map> <host>` — exit 0 bij succes; exit 1 als een pagina niet in orde is (geen `</head>`, markering zonder partner) of er geen `.html` is; exit 2 bij een ongeldige map of host. Wijzigt niets als de controle faalt. Na succes: elke `.html` heeft exact één noindex-meta, geen analytics-blokken; `CNAME` bevat `<host>`; `.nojekyll` bestaat.

- [ ] **Step 1: Schrijf de falende test**

`tests/test_staging_envelope.sh`:

```bash
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
```

- [ ] **Step 2: Draai de test en zie hem falen**

Run: `bash tests/run.sh`
Expected: FAIL. `test_staging_envelope.sh` meldt `✗ script faalde` (het script bestaat nog niet); `test_build.sh` blijft groen.

- [ ] **Step 3: Schrijf `staging-envelope.sh`**

`scripts/staging-envelope.sh`:

```bash
#!/usr/bin/env bash
# Past het staging-omhulsel toe op een gebouwde site (spec §5.1):
#   1. analytics-blokken eruit (alles tussen <!-- analytics:start --> en <!-- analytics:end -->)
#   2. <meta name="robots" content="noindex, nofollow"> vóór </head>, als die er nog niet staat
#   3. CNAME met de staging-host
#   4. .nojekyll, zodat Pages in site-staging de bestanden niet door Jekyll haalt
#
# Eerst wordt elk bestand gecontroleerd; pas als alles in orde is, wordt er iets
# gewijzigd. Zo komt er nooit een half omhulde (en dus indexeerbare) staging online.
#
# Gebruik: scripts/staging-envelope.sh <map> <host>
set -euo pipefail

DIR="${1:?gebruik: staging-envelope.sh <map> <host>}"
HOST="${2:?gebruik: staging-envelope.sh <map> <host>}"
HOST_RE='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'

if [[ ! -d "$DIR" ]]; then
  echo "staging-envelope: map bestaat niet: $DIR" >&2
  exit 2
fi
if [[ ! "$HOST" =~ $HOST_RE ]]; then
  echo "staging-envelope: ongeldige host '$HOST' (alleen een hostnaam, zonder https:// of /)" >&2
  exit 2
fi

pages=()
while IFS= read -r -d '' f; do pages+=("$f"); done < <(find "$DIR" -type f -name '*.html' -print0)
if [[ ${#pages[@]} -eq 0 ]]; then
  echo "staging-envelope: geen .html-bestanden in $DIR" >&2
  exit 1
fi

# Controleren: elke pagina heeft </head> en alleen complete analytics-blokken.
for f in "${pages[@]}"; do
  if ! perl -0777 -ne '
      (my $rest = $_) =~ s/<!-- analytics:start -->.*?<!-- analytics:end -->//gs;
      die "analytics-markering zonder partner\n" if $rest =~ /<!-- analytics:(?:start|end) -->/;
      die "geen </head>\n" unless m{</head>}i;
    ' "$f"; then
    echo "staging-envelope: $f is niet in orde; er is niets gewijzigd" >&2
    exit 1
  fi
done

# Wijzigen.
for f in "${pages[@]}"; do
  perl -0777 -pi -e '
    s/[ \t]*<!-- analytics:start -->.*?<!-- analytics:end -->[ \t]*\n?//gs;
    s{(</head>)}{<meta name="robots" content="noindex, nofollow">\n$1}i
      unless /<meta name="robots" content="noindex/;
  ' "$f"
done
printf '%s\n' "$HOST" > "$DIR/CNAME"
touch "$DIR/.nojekyll"

echo "staging-envelope: ${#pages[@]} pagina's met noindex, CNAME $HOST"
```

- [ ] **Step 4: Draai de test; alleen "de echte site" faalt nog**

Run: `chmod +x scripts/staging-envelope.sh && bash tests/run.sh`
Expected: FAIL, met precies één rode regel: `✗ index.html bevat onterecht 'hotjar'` onder "omhulsel: de echte site". Het Hotjar-blok in `index.html` heeft nog geen markeringen.

- [ ] **Step 5: Zet de markeringen rond het Hotjar-blok**

In `index.html`: voeg direct boven regel 19 (`<!-- Hotjar Tracking Code for https://www.businessdatasolutions.nl -->`) een regel in en direct onder regel 34 (de `</script>` die het blok sluit, vóór `</head>`) een regel. Resultaat:

```html
    <link rel="stylesheet" href="styles.css" />
    <!-- analytics:start -->
    <!-- Hotjar Tracking Code for https://www.businessdatasolutions.nl -->
    <script>
      (function (h, o, t, j, a, r) {
        …ongewijzigd…
      })(window, document, "https://static.hotjar.com/c/hotjar-", ".js?sv=");
    </script>
    <!-- analytics:end -->
  </head>
```

- [ ] **Step 6: Draai de tests en zie ze slagen**

Run: `bash tests/run.sh`
Expected: PASS, `Alle tests geslaagd.`

Run ook: `git diff --stat index.html`
Expected: `1 file changed, 2 insertions(+)`

- [ ] **Step 7: Commit**

```bash
git add tests/test_staging_envelope.sh scripts/staging-envelope.sh index.html
git commit -F - <<'EOF'
feat(ci): staging-omhulsel met noindex, CNAME en zonder analytics

staging-envelope.sh controleert eerst elke pagina en wijzigt pas als alles in
orde is. index.html krijgt analytics-markeringen rond Hotjar, zodat staging-
bezoek de statistieken niet vervuilt.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: `push-staging.sh`

**Files:**
- Create: `tests/test_push_staging.sh`
- Create: `scripts/push-staging.sh`

**Interfaces:**
- Consumes: `scripts/build.sh [uitvoermap]` (Task 1); `scripts/staging-envelope.sh <map> <host>` (Task 2); testhulpjes (Task 1).
- Produces: `scripts/push-staging.sh <map>`, omgeving `DEPLOY_KEY` (privé-sleutel; vereist als de remote met `git@` begint) en `STAGING_REMOTE` (standaard `git@github.com:businessdatasolutions/site-staging.git`). Exit 0 na een geslaagde force-push van één commit naar `main`; exit 1 bij een build zonder omhulsel of een lege `DEPLOY_KEY`; exit 2 als de map niet bestaat. Maakt geen `.git` aan in `<map>` en pusht `.build-output` niet mee.

- [ ] **Step 1: Schrijf de falende test**

`tests/test_push_staging.sh`:

```bash
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
```

- [ ] **Step 2: Draai de test en zie hem falen**

Run: `bash tests/run.sh`
Expected: FAIL. `test_push_staging.sh` meldt `✗ eerste push faalde` en `✗ main heeft 0 commits, verwacht 1`.

- [ ] **Step 3: Schrijf `push-staging.sh`**

`scripts/push-staging.sh`:

```bash
#!/usr/bin/env bash
# Pusht een omhulde build naar site-staging als één verse commit op main
# (force-push; de staging-repo bouwt zo geen geschiedenis op).
#
# Weigert een build zonder staging-omhulsel: zonder CNAME of met een pagina
# zonder noindex zou staging indexeerbaar online komen.
#
# Gebruik:  scripts/push-staging.sh <map>
# Omgeving: DEPLOY_KEY      privé-sleutel; vereist voor een ssh-remote (git@…)
#           STAGING_REMOTE  standaard git@github.com:businessdatasolutions/site-staging.git
#                           (de tests gebruiken een lokale bare repo)
set -euo pipefail

DIR="${1:?gebruik: push-staging.sh <map>}"
REMOTE="${STAGING_REMOTE:-git@github.com:businessdatasolutions/site-staging.git}"
NOINDEX='<meta name="robots" content="noindex'
# Bron: https://api.github.com/meta (ssh_keys)
GITHUB_HOST_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'

if [[ ! -d "$DIR" ]]; then
  echo "push-staging: map bestaat niet: $DIR" >&2
  exit 2
fi
if [[ ! -s "$DIR/CNAME" ]]; then
  echo "push-staging: $DIR/CNAME ontbreekt; draai eerst staging-envelope.sh" >&2
  exit 1
fi
zonder=$(find "$DIR" -type f -name '*.html' -exec grep -L -F "$NOINDEX" {} + || true)
if [[ -n "$zonder" ]]; then
  echo "push-staging: pagina's zonder noindex, ik push niet:" >&2
  echo "$zonder" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ "$REMOTE" == git@* ]]; then
  if [[ -z "${DEPLOY_KEY:-}" ]]; then
    echo "push-staging: DEPLOY_KEY is leeg; controleer het secret STAGING_DEPLOY_KEY in de omgeving staging" >&2
    exit 1
  fi
  printf '%s\n' "$DEPLOY_KEY" > "$WORK/key"
  chmod 600 "$WORK/key"
  printf '%s\n' "$GITHUB_HOST_KEY" > "$WORK/known_hosts"
  export GIT_SSH_COMMAND="ssh -i $WORK/key -o IdentitiesOnly=yes -o UserKnownHostsFile=$WORK/known_hosts -o StrictHostKeyChecking=yes"
fi

cd "$DIR"
g() { git --git-dir="$WORK/repo.git" --work-tree="$PWD" "$@"; }
sha="${GITHUB_SHA:-onbekend}"
g init -q -b main
g add -A -- . ':(exclude).build-output'
g -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "staging: ${GITHUB_REF_NAME:-lokaal}@${sha:0:7}"
g push -q --force "$REMOTE" main
echo "push-staging: $DIR → $REMOTE (main)"
```

- [ ] **Step 4: Draai de tests en zie ze slagen**

Run: `chmod +x scripts/push-staging.sh && bash tests/run.sh`
Expected: PASS, `Alle tests geslaagd.`

- [ ] **Step 5: Commit**

```bash
git add tests/test_push_staging.sh scripts/push-staging.sh
git commit -F - <<'EOF'
feat(ci): push-staging.sh pusht alleen een omhulde build

Eén verse commit per deploy naar site-staging, met de ssh-hostsleutel van
GitHub vastgepind. Weigert een build zonder CNAME of noindex en geeft een
duidelijke melding als het deploy-secret ontbreekt.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Workflow, workflow-invarianten en README

**Files:**
- Create: `tests/test_workflow.sh`
- Create: `.github/workflows/deploy.yml`
- Modify: `README.md` (nieuwe sectie "Deployen" onderaan)

**Interfaces:**
- Consumes: `bash tests/run.sh`, `scripts/build.sh _site`, `scripts/staging-envelope.sh <map> <host>`, `scripts/push-staging.sh <map>` met `DEPLOY_KEY` (Task 1–3).
- Produces: workflow `Deploy` (bestand `deploy.yml`) met jobs `build`, `deploy-staging`, `deploy-production`; artifactnaam `github-pages`; omgevingen `staging` (secret `STAGING_DEPLOY_KEY`) en `github-pages`.

- [ ] **Step 1: Schrijf de falende invariantentest**

`tests/test_workflow.sh`:

```bash
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

finish
```

- [ ] **Step 2: Draai de test en zie hem falen**

Run: `bash tests/run.sh`
Expected: FAIL. `test_workflow.sh` meldt `✗ ontbreekt: …/.github/workflows/deploy.yml`.

- [ ] **Step 3: Schrijf de workflow**

`.github/workflows/deploy.yml`:

```yaml
# Deploy: build → staging (automatisch) → productie (na goedkeuring).
# Ontwerp: docs/superpowers/specs/2026-10-04-ci-cd-staging-prod-design.md
name: Deploy

on:
  push:
    branches:
      - master
      - ci/pipeline   # TIJDELIJK (spec §8): weghalen vóór de merge naar master
  pull_request:
    branches: [master]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Tests
        run: bash tests/run.sh

      - name: Build
        run: scripts/build.sh _site

      - name: Linkcheck (interne links en ankers)
        uses: lycheeverse/lychee-action@v2.9.0
        with:
          args: >-
            --offline
            --include-fragments
            --index-files index.html
            --root-dir ${{ github.workspace }}/_site
            --no-progress
            '_site/**/*.html'

      - name: Artifact uploaden
        uses: actions/upload-pages-artifact@v5
        with:
          path: _site
          retention-days: 30   # standaard 1 dag; een goedkeuring mag tot 30 dagen wachten

  deploy-staging:
    if: github.event_name != 'pull_request'
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging
      url: https://staging.businessdatasolutions.nl
    concurrency:
      group: staging
      cancel-in-progress: true
    steps:
      - uses: actions/checkout@v7

      - name: Artifact downloaden
        uses: actions/download-artifact@v8
        with:
          name: github-pages
          path: ${{ runner.temp }}/artifact

      - name: Uitpakken
        run: |
          mkdir -p "$RUNNER_TEMP/staging"
          tar -xf "$RUNNER_TEMP/artifact/artifact.tar" -C "$RUNNER_TEMP/staging"

      - name: Staging-omhulsel
        run: scripts/staging-envelope.sh "$RUNNER_TEMP/staging" staging.businessdatasolutions.nl

      - name: Push naar site-staging
        env:
          DEPLOY_KEY: ${{ secrets.STAGING_DEPLOY_KEY }}
        run: scripts/push-staging.sh "$RUNNER_TEMP/staging"

  deploy-production:
    if: github.ref == 'refs/heads/master'
    needs: [build, deploy-staging]
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    concurrency:
      group: production
      cancel-in-progress: false
    permissions:
      pages: write
      id-token: write
    steps:
      - name: Publiceren
        id: deployment
        uses: actions/deploy-pages@v5
```

- [ ] **Step 4: Draai de tests en zie ze slagen; lint de workflow**

Run: `bash tests/run.sh`
Expected: PASS, `Alle tests geslaagd.`

Run (actionlint als losse binary in `$SCRATCH`, geen systeeminstallatie):

```bash
gh release download --repo rhysd/actionlint --pattern '*_darwin_arm64.tar.gz' --dir "$SCRATCH"
tar -xzf "$SCRATCH"/actionlint_*_darwin_arm64.tar.gz -C "$SCRATCH" actionlint
"$SCRATCH/actionlint" .github/workflows/deploy.yml && echo "actionlint: schoon"
```

Expected: `actionlint: schoon` (geen meldingen).

- [ ] **Step 5: Linkcheck lokaal op de echte build (moet slagen)**

```bash
curl -sfL -o "$SCRATCH/lychee.tgz" https://github.com/lycheeverse/lychee/releases/download/lychee-v0.24.2/lychee-aarch64-apple-darwin.tar.gz
tar -xzf "$SCRATCH/lychee.tgz" -C "$SCRATCH"
LYCHEE="$(find "$SCRATCH" -type f -name lychee | head -1)"
scripts/build.sh _site
"$LYCHEE" --offline --include-fragments --index-files index.html --root-dir "$PWD/_site" --no-progress '_site/**/*.html'; echo "EXIT=$?"
```

Expected: samenvatting met `🚫 0 Errors` (externe links tellen als *Excluded*) en `EXIT=0`. Dit bewijst Review Focus 4, eerste helft: externe links, `mailto:`/`tel:` en `href="#"` laten de check niet falen.

- [ ] **Step 6: Linkcheck lokaal met een kapotte link (moet falen)**

```bash
perl -0777 -pi -e 's{</body>}{<a href="/bestaat-niet/">x</a></body>}' _site/blog/index.html
"$LYCHEE" --offline --include-fragments --index-files index.html --root-dir "$PWD/_site" --no-progress '_site/**/*.html'; echo "EXIT=$?"
scripts/build.sh _site   # herstel
```

Expected: een `[ERROR] …/_site/bestaat-niet … File not found` en `EXIT=2`. Daarmee is Review Focus 4, tweede helft, aangetoond.

- [ ] **Step 7: Voeg de sectie "Deployen" toe aan de README**

Voeg onderaan `README.md` toe:

````markdown
## Deployen

Elke wijziging gaat eerst naar staging en pas na goedkeuring naar productie.
Achtergrond: [ontwerpspec](docs/superpowers/specs/2026-10-04-ci-cd-staging-prod-design.md).

| Omgeving | Adres | Wanneer |
|---|---|---|
| Staging | https://staging.businessdatasolutions.nl | Automatisch na elke push naar `master`, of handmatig vanaf elke branch |
| Productie | https://www.businessdatasolutions.nl | Na goedkeuring in GitHub |

### Iets live zetten

1. Push naar `master` (of merge een pull request).
2. Wacht tot de workflow **Deploy** staging heeft bijgewerkt en controleer https://staging.businessdatasolutions.nl.
3. Open de run in de Actions-tab → **Review deployments** → vink `github-pages` aan → **Approve and deploy**.

### Een andere branch op staging zetten (bijv. het redesign)

```bash
gh workflow run deploy.yml --ref redesign
```

Of: Actions → Deploy → **Run workflow** → kies de branch. Er is één staging-plek: de laatste deploy wint.

### Wat er gepubliceerd wordt

Alleen wat in `PUBLIC` in `scripts/build.sh` staat (nu `index.html`, `styles.css`, `blog/`, `images/`).
Een nieuw publiek bestand of een nieuwe publieke map moet daar bij.

### Analytics

Zet trackingcode tussen `<!-- analytics:start -->` en `<!-- analytics:end -->`. Staging haalt alles daartussen weg.

### Lokaal testen

- `bash tests/run.sh`: tests voor de scripts en de workflow-afspraken
- `scripts/build.sh`: bouwt de site in `_site/`

### Terugdraaien

- **Fout op productie:** `git revert <commit>`, pushen, staging controleren, goedkeuren.
- **Pijplijn kapot:**
  `gh api -X PUT repos/businessdatasolutions/site/pages -f build_type=legacy -f "source[branch]=master" -f "source[path]=/"`.
  Daarna publiceert `master` weer direct, zonder staging en zonder goedkeuring.

### Let op

- Maak deze repo niet privé. Op het gratis plan vervalt dan de verplichte goedkeuring en gaat alles direct live.
- Een goedkeuring kan tot 30 dagen wachten; daarna verlopen de run en het build-artifact.
- Werk nooit in `businessdatasolutions/site-staging`: elke deploy overschrijft die repo.
````

- [ ] **Step 8: Commit**

```bash
git add tests/test_workflow.sh .github/workflows/deploy.yml README.md
git commit -F - <<'EOF'
feat(ci): workflow Deploy met staging en goedkeuring voor productie

build (tests, allowlist-build, linkcheck, artifact 30 dagen) → deploy-staging
(omhulsel + push naar site-staging) → deploy-production (deploy-pages achter
de omgeving github-pages). README beschrijft goedkeuren en terugdraaien.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: GitHub inrichten voor staging

**Files:** geen wijzigingen in de repo.

**Interfaces:**
- Consumes: niets uit eerdere taken.
- Produces: repo `businessdatasolutions/site-staging` (publiek, leeg); deploy key `deploy from site` met schrijfrecht; omgeving `staging` in `site` met secret `STAGING_DEPLOY_KEY`.

- [ ] **Step 1: STOP — vraag Witek om akkoord**

Meld: "Ik ga nu de publieke repo `businessdatasolutions/site-staging` aanmaken, een deploy key koppelen en de omgeving `staging` met secret in `site` zetten. De live site verandert niet. Akkoord?" Ga pas verder na een expliciet ja.

- [ ] **Step 2: Maak de staging-repo aan**

```bash
gh repo create businessdatasolutions/site-staging --public \
  --description "Staging-hosting voor businessdatasolutions/site. Niet handmatig bewerken: elke deploy overschrijft deze repo." \
  --homepage https://staging.businessdatasolutions.nl \
  --disable-issues --disable-wiki
gh repo view businessdatasolutions/site-staging --json visibility,description --jq '.visibility + " | " + .description'
```

Expected: `PUBLIC | Staging-hosting voor businessdatasolutions/site. …`

- [ ] **Step 3: Maak de deploy key en het secret; verwijder de lokale sleutel**

```bash
gh api -X PUT repos/businessdatasolutions/site/environments/staging --jq .name
ssh-keygen -q -t ed25519 -N "" -C "deploy from site" -f "$SCRATCH/staging_deploy_key"
gh repo deploy-key add "$SCRATCH/staging_deploy_key.pub" --repo businessdatasolutions/site-staging --allow-write --title "deploy from site"
gh secret set STAGING_DEPLOY_KEY --repo businessdatasolutions/site --env staging < "$SCRATCH/staging_deploy_key"
rm -f "$SCRATCH/staging_deploy_key" "$SCRATCH/staging_deploy_key.pub"
```

Expected: eerste regel `staging`; daarna bevestigingen van `gh` voor de deploy key en het secret.

- [ ] **Step 4: Controleer**

```bash
gh repo deploy-key list --repo businessdatasolutions/site-staging
gh secret list --repo businessdatasolutions/site --env staging
ls "$SCRATCH"/staging_deploy_key* 2>/dev/null || echo "lokale sleutel verwijderd"
```

Expected: één key `deploy from site` met `read-write`; één secret `STAGING_DEPLOY_KEY`; `lokale sleutel verwijderd`.

---

### Task 6: DNS, eerste staging-deploy en Pages voor staging

**Files:** geen wijzigingen in de repo.

**Interfaces:**
- Consumes: workflow uit Task 4 (met de tijdelijke trigger op `ci/pipeline`); repo, key en secret uit Task 5.
- Produces: werkende `https://staging.businessdatasolutions.nl`.

- [ ] **Step 1: Witek zet het DNS-record bij Mijndomein**

Vraag Witek om bij Mijndomein (DNS-beheer van `businessdatasolutions.nl`) dit record toe te voegen:

| Type | Naam | Waarde |
|---|---|---|
| CNAME | `staging` | `businessdatasolutions.github.io.` |

Controleer (herhaal tot het klopt; doorgaans binnen een uur):

```bash
dig +short CNAME staging.businessdatasolutions.nl
```

Expected: `businessdatasolutions.github.io.`

- [ ] **Step 2: Push `ci/pipeline` en volg de run**

```bash
git push -u origin ci/pipeline
RUN=$(gh run list --workflow deploy.yml --branch ci/pipeline --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN" --json jobs --jq '.jobs[] | "\(.name): \(.status) \(.conclusion)"'
```

Herhaal de laatste regel tot er niets meer op `in_progress` of `queued` staat (gebruik een until-lus of Monitor, geen `gh run watch`).
Expected:
```
build: completed success
deploy-staging: completed success
deploy-production: completed skipped
```
Daarmee is A2 (eerste keer) aangetoond. Faalt `deploy-staging` op de push: `gh run view "$RUN" --log-failed` en controleer Task 5 stap 4.

- [ ] **Step 3: Zet Pages aan voor `site-staging`**

```bash
gh api -X POST repos/businessdatasolutions/site-staging/pages -f "source[branch]=main" -f "source[path]=/" --jq .html_url
gh api -X PUT repos/businessdatasolutions/site-staging/pages -f cname=staging.businessdatasolutions.nl
gh api repos/businessdatasolutions/site-staging/pages --jq '{status, cname, cert: .https_certificate.state}'
```

Expected: `cname` is `staging.businessdatasolutions.nl`. `cert` gaat via `new`/`authorization_created` naar `approved`; dat kan van minuten tot een paar uur duren. Herhaal de laatste regel tot `approved`, en dan:

```bash
gh api -X PUT repos/businessdatasolutions/site-staging/pages -F https_enforced=true
```

- [ ] **Step 4: Controleer staging (A3)**

```bash
B=https://staging.businessdatasolutions.nl
for p in / /blog/ /blog/branches-not-time/ /blog/three-model-calls/; do
  curl -fsS "$B$p" -o "$SCRATCH/p.html" \
    && echo "$p  200  noindex:$(grep -c 'name="robots" content="noindex' "$SCRATCH/p.html")  hotjar:$(grep -ci hotjar "$SCRATCH/p.html")"
done
curl -sI "http://staging.businessdatasolutions.nl/" | head -1
```

Expected: vier regels `200  noindex:1  hotjar:0`, en de http-aanvraag geeft een `301` (doorsturing naar https). Klik daarna in een browser door de navigatie (Home → Blog → een post → terug); alle links werken.

---

### Task 7: Productie overzetten

**Files:**
- Modify: `.github/workflows/deploy.yml` (tijdelijke trigger weg)
- Modify: `tests/test_workflow.sh` (bewaakt dat de trigger weg is)

**Interfaces:**
- Consumes: alles uit Task 1–6.
- Produces: `www.businessdatasolutions.nl` gepubliceerd via de workflow, achter Witeks goedkeuring.

- [ ] **Step 1: Schrijf de falende controle op de tijdelijke trigger**

Voeg in `tests/test_workflow.sh` vóór `finish` toe:

```bash
assert_not_contains "$WF" "ci/pipeline"                           # tijdelijke trigger is weg (spec §8 stap 6)
```

Run: `bash tests/run.sh`
Expected: FAIL met `✗ deploy.yml bevat onterecht 'ci/pipeline'`.

- [ ] **Step 2: Haal de tijdelijke trigger weg**

In `.github/workflows/deploy.yml` wordt het `push`-blok:

```yaml
  push:
    branches: [master]
```

Run: `bash tests/run.sh`
Expected: PASS, `Alle tests geslaagd.`

- [ ] **Step 3: Commit en push**

```bash
git add .github/workflows/deploy.yml tests/test_workflow.sh
git commit -F - <<'EOF'
chore(ci): tijdelijke trigger op ci/pipeline verwijderd

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git push
```

Expected: deze push start **geen** nieuwe run (`gh run list --workflow deploy.yml --limit 1` toont nog de run uit Task 6).

- [ ] **Step 4: STOP — vraag Witek om akkoord voor de overstap**

Meld: "Staging werkt. Ik ga nu Pages van `site` omzetten naar publiceren via Actions, de goedkeuring instellen en `ci/pipeline` via een pull request naar `master` mergen. De huidige site blijft online tot jij de eerste deploy goedkeurt. Akkoord?" Ga pas verder na een expliciet ja.

- [ ] **Step 5: Zet Pages om naar Actions en controleer dat de site online blijft**

```bash
gh api -X PUT repos/businessdatasolutions/site/pages -f build_type=workflow
gh api repos/businessdatasolutions/site/pages --jq '{build_type, cname, https_enforced}'
curl -sI https://www.businessdatasolutions.nl/ | head -1
```

Expected: `{"build_type":"workflow","cname":"www.businessdatasolutions.nl","https_enforced":true}` en `HTTP/2 200`.

- [ ] **Step 6: Stel de goedkeuring en de branchregel in op `github-pages`**

```bash
gh api -X PUT repos/businessdatasolutions/site/environments/github-pages --input - <<'EOF'
{"reviewers":[{"type":"User","id":5702329}],"prevent_self_review":false,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
gh api repos/businessdatasolutions/site/environments/github-pages/deployment-branch-policies --jq '[.branch_policies[].name]'
```

Staat `master` niet in de lijst:

```bash
gh api -X POST repos/businessdatasolutions/site/environments/github-pages/deployment-branch-policies -f name=master -f type=branch --jq .name
```

Controleer:

```bash
gh api repos/businessdatasolutions/site/environments/github-pages \
  --jq '{reviewers: [.protection_rules[] | select(.type=="required_reviewers") | .reviewers[].reviewer.login], branch_policy: .deployment_branch_policy}'
gh api repos/businessdatasolutions/site/environments/github-pages/deployment-branch-policies --jq '[.branch_policies[].name]'
```

Expected: `reviewers` is `["witusj"]`, `custom_branch_policies` is `true`, en de lijst met branchregels is precies `["master"]`.

- [ ] **Step 7: Open de pull request en wacht op de check**

```bash
gh pr create --base master --head ci/pipeline \
  --title "CI/CD: staging en productie via GitHub Actions" \
  --body-file - <<'EOF'
Elke push naar `master` gaat automatisch naar https://staging.businessdatasolutions.nl;
productie gaat pas live na goedkeuring op de omgeving `github-pages`, met hetzelfde build-artifact.

- Ontwerp: `docs/superpowers/specs/2026-10-04-ci-cd-staging-prod-design.md`
- Plan: `docs/superpowers/plans/2026-10-04-ci-cd-staging-prod.md`
- Staging is al getest vanaf deze branch (noindex, geen Hotjar, navigatie werkt).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
gh pr checks ci/pipeline
```

Herhaal `gh pr checks ci/pipeline` tot er niets meer loopt.
Expected: `build  pass`; de deploy-jobs verschijnen als `skipping`.

- [ ] **Step 8: Merge en volg de run tot de goedkeuring**

```bash
gh pr merge ci/pipeline --merge
RUN=$(gh run list --workflow deploy.yml --branch master --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN" --json jobs --jq '.jobs[] | "\(.name): \(.status) \(.conclusion)"'
```

Herhaal de laatste regel tot `deploy-staging` klaar is.
Expected:
```
build: completed success
deploy-staging: completed success
deploy-production: waiting
```

- [ ] **Step 9: Witek keurt goed**

Geef Witek de link (`gh run view "$RUN" --json url --jq .url`) en vraag hem: **Review deployments** → vink `github-pages` aan → **Approve and deploy**. Keur niet zelf goed.

Daarna, herhalen tot `deploy-production` klaar is:

```bash
gh run view "$RUN" --json jobs --jq '.jobs[] | "\(.name): \(.status) \(.conclusion)"'
```

Expected: `deploy-production: completed success`.

- [ ] **Step 10: Controleer productie (A4)**

```bash
curl -fsS https://www.businessdatasolutions.nl/ -o "$SCRATCH/prod.html"
echo "markering:$(grep -c 'analytics:start' "$SCRATCH/prod.html")  noindex:$(grep -c 'name="robots" content="noindex' "$SCRATCH/prod.html")  hotjar:$(grep -c 'static.hotjar.com' "$SCRATCH/prod.html")"
curl -sI https://www.businessdatasolutions.nl/ | head -1
```

Expected: `markering:1  noindex:0  hotjar:1` en `HTTP/2 200`. De markering staat alleen in de nieuwe build en bewijst dus dat de deploy live is. Staat er `markering:0`, dan serveert de CDN nog de oude versie: herhaal tot 10 minuten later.

- [ ] **Step 11: Lokale `master` bijwerken**

```bash
git switch master && git pull --ff-only
git log --oneline -3
```

Expected: de merge-commit van de pull request bovenaan.

---

### Task 8: Natesten na de overstap

**Files:**
- Modify: `README.md` (gedrag van gelijktijdige goedkeuringen vastleggen)

**Interfaces:**
- Consumes: de live pijplijn uit Task 7.
- Produces: A1 en A2 aangetoond op `master`; README beschrijft wat er gebeurt bij twee wachtende goedkeuringen.

- [ ] **Step 1: A2 met een echte `workflow_dispatch`**

```bash
git switch -c test/staging-dispatch master
git push -u origin test/staging-dispatch
gh workflow run deploy.yml --ref test/staging-dispatch
RUN=$(gh run list --workflow deploy.yml --branch test/staging-dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN" --json event,jobs --jq '.event, (.jobs[] | "\(.name): \(.status) \(.conclusion)")'
```

Herhaal de laatste regel tot alles klaar is.
Expected: `workflow_dispatch`, daarna `build: completed success`, `deploy-staging: completed success`, `deploy-production: completed skipped`.

Opruimen:

```bash
git switch master
git push origin --delete test/staging-dispatch
git branch -D test/staging-dispatch
```

- [ ] **Step 2: A1 met een pull request met een kapotte link**

Meld Witek dat er kort een test-PR (draft) in de publieke repo verschijnt.

```bash
git switch -c test/kapotte-link master
perl -0777 -pi -e 's{</body>}{<a href="/bestaat-niet/">test</a></body>}' blog/index.html
git commit -am "test: kapotte interne link (niet mergen)"
git push -u origin test/kapotte-link
gh pr create --draft --base master --head test/kapotte-link --title "TEST: kapotte link (niet mergen)" --body "Controleert dat de linkcheck faalt. Wordt direct gesloten."
gh pr checks test/kapotte-link
```

Herhaal de laatste regel tot er niets meer loopt.
Expected: `build  fail`. Controleer de oorzaak:

```bash
RUN=$(gh run list --workflow deploy.yml --branch test/kapotte-link --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN" --log-failed | grep -m1 "bestaat-niet"
```

Expected: een regel met `bestaat-niet` en `File not found`.

Opruimen:

```bash
gh pr close test/kapotte-link --delete-branch
git switch master && git branch -D test/kapotte-link
```

- [ ] **Step 3: Observeer twee wachtende goedkeuringen (Review Focus 5)**

```bash
gh workflow run deploy.yml --ref master
```

Wacht tot deze run op `deploy-production: waiting` staat, en start dan een tweede:

```bash
gh workflow run deploy.yml --ref master
gh run list --workflow deploy.yml --limit 3 --json databaseId,status,conclusion,createdAt \
  --jq '.[] | "\(.databaseId) \(.status) \(.conclusion) \(.createdAt)"'
```

Herhaal de laatste regel tot de `deploy-production`-job van de tweede run een status heeft: `waiting`, `queued`/`pending`, of `completed cancelled`. Wacht niet tot hij `waiting` wordt: de waarschijnlijkste uitkomst is dat een job die op goedkeuring wacht zijn concurrency-groep vasthoudt, zodat de tweede op `queued` blijft staan zolang de eerste wacht. Kijk de job-status zo na:

```bash
for r in $(gh run list --workflow deploy.yml --limit 2 --json databaseId --jq '.[].databaseId'); do
  echo "$r: $(gh run view "$r" --json jobs --jq '.jobs[] | select(.name=="deploy-production") | .status + " " + .conclusion')"
done
```

Noteer welke van de drie uitkomsten optreedt.

Ruim op: vraag Witek de **oudste** run af te wijzen (*Review deployments* → *Reject*). Staat de tweede op `queued`, dan schuift die daarna door naar `waiting`; laat Witek die goedkeuren. Beide bevatten dezelfde code, dus dat is veilig.

- [ ] **Step 4: Leg het gedrag vast in de README**

Voeg onder "### Let op" in `README.md` één regel toe die past bij de observatie in stap 3:

- Bij automatische annulering:
  `- Wacht er al een goedkeuring en start er een nieuwe run, dan annuleert GitHub de oudere. Keur altijd de nieuwste goed.`
- Als beide blijven wachten:
  `- Wachten er twee runs op goedkeuring, wijs dan de oudere af en keur de nieuwste goed; anders kan een oudere versie de nieuwere overschrijven.`
- Als de tweede in de rij blijft staan (`queued`) zolang de eerste wacht:
  `- Wacht er al een run op goedkeuring, dan staat een nieuwere run daarachter in de rij. Is er inmiddels nieuwer werk, wijs dan de oudste af: de nieuwste schuift door en vraagt opnieuw om goedkeuring. Een derde run annuleert de middelste, zodat altijd de nieuwste overblijft.`

```bash
git add README.md
git commit -F - <<'EOF'
docs(readme): gedrag bij twee wachtende goedkeuringen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git push
```

Expected: de push start een run. `README.md` staat niet in de allowlist en verandert dus niets aan de site, maar de run wacht toch op goedkeuring. Vraag Witek die goed te keuren (of af te wijzen; het resultaat is identiek).

---

### Task 9 (aanbevolen): kale domein en domeinverificatie

**Files:** geen wijzigingen in de repo.

**Interfaces:**
- Consumes: Pages-instellingen uit Task 7.
- Produces: `businessdatasolutions.nl` stuurt door naar `www`; het domein is geverifieerd in de organisatie.

- [ ] **Step 1: Witek past het kale domein aan bij Mijndomein**

Eerst controleren of Mijndomein op `businessdatasolutions.nl` een URL-doorsturing heeft; zo ja, uitzetten. Vervang dan het A-record van `@` (nu `213.249.67.10`) door vier A-records:

| Type | Naam | Waarde |
|---|---|---|
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |

Controleer (herhaal tot het klopt):

```bash
dig +short A businessdatasolutions.nl | sort
```

Expected: precies de vier adressen hierboven.

- [ ] **Step 2: Controleer de doorsturing (A6)**

```bash
curl -sI http://businessdatasolutions.nl/ | grep -iE '^(HTTP|location)'
curl -sI https://businessdatasolutions.nl/ | grep -iE '^(HTTP|location)'
gh api repos/businessdatasolutions/site/pages --jq '.https_certificate.domains'
```

Expected: beide geven `301` met `location: https://www.businessdatasolutions.nl/`, en de certificaatlijst bevat ook `businessdatasolutions.nl`. GitHub vraagt het certificaat voor het kale domein zelf aan; dat kan tot 24 uur duren. Geeft https na 24 uur nog een certificaatfout: meld het aan Witek en wacht op overleg. Het custom domain opnieuw instellen haalt de site kort offline.

- [ ] **Step 3: Witek verifieert het domein in de organisatie**

Witek opent https://github.com/organizations/businessdatasolutions/settings/pages → **Add a domain** → `businessdatasolutions.nl`. GitHub toont een TXT-record (naam `_github-pages-challenge-businessdatasolutions`, plus een waarde). Witek zet dat bij Mijndomein en klikt daarna op **Verify**.

Controleer:

```bash
dig +short TXT _github-pages-challenge-businessdatasolutions.businessdatasolutions.nl
```

Expected: de waarde die GitHub toonde. Op de instellingenpagina staat het domein als **Verified**.
