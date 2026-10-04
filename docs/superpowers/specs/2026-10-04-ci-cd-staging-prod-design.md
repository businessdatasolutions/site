# CI/CD met staging en productie — ontwerp

- **Datum:** 2026-10-04
- **Repo:** `businessdatasolutions/site` (lokaal: `~/Projects/site`)
- **Status:** ontwerp goedgekeurd in gesprek; spec ter review
- **Vervolg:** implementatieplan, daarna het redesign met het stylebook (`brand-project/stylebook`) als apart deelproject

## 1. Doel

De website gaat opnieuw ontworpen worden. Voordat dat begint, moet er een pijplijn liggen die elke wijziging eerst op een echte staging-URL zet en pas na een bewuste goedkeuring op `www.businessdatasolutions.nl`.

**Succes betekent:**

1. Een push naar `master` zet staging automatisch bij.
2. Productie gaat alleen live nadat Witek de deploy goedkeurt.
3. Wat op productie komt, is exact de build die op staging stond.
4. Staging wordt niet geïndexeerd door zoekmachines en vervuilt de statistieken niet.
5. De live site is tijdens de overstap geen moment onbereikbaar.

## 2. Uitgangssituatie

- Statische site: `index.html`, `styles.css`, `blog/` (overzicht + twee posts), `images/` (± 8 MB). Geen build-stap.
- GitHub Pages in **legacy**-modus: publiceert `master` / root direct. Custom domain `www.businessdatasolutions.nl`, HTTPS afgedwongen, certificaat geldig tot 2026-12-05.
- Repo is **publiek**; de organisatie zit op het **gratis** plan.
- De blog linkt vanaf de root (`href="/"`, `href="/blog/…"`). Een site op een sub-pad (bijv. `…github.io/site-staging/`) breekt daardoor de navigatie.
- `index.html` laadt Hotjar (`hjid 2243063`); de blogpagina's niet.
- DNS staat bij Mijndomein (`nsn1/nsn2.mijndomein.nl`). Het kale domein wijst naar 213.249.67.10 (Mijndomein), niet naar GitHub; daarom werkt de site alleen met `www`. `staging.businessdatasolutions.nl` resolvet nu ook naar 213.249.67.10 (vermoedelijk een wildcard-record).

## 3. Besluiten

| # | Besluit | Reden |
|---|---|---|
| B1 | Alles binnen GitHub (Actions + Pages) | Wens van de eigenaar; geen extra dienst |
| B2 | Staging is **publiek**, met `noindex` | GitHub Pages is op het gratis plan altijd publiek; delen van een link voor feedback is handig |
| B3 | Staging op `staging.businessdatasolutions.nl` | Root-relatieve links vereisen een eigen (sub)domein |
| B4 | Staging wordt gehost in een aparte repo `businessdatasolutions/site-staging` | Pages kent één site per repo |
| B5 | Eén branch (`master`); promotie naar prod via een **verplichte reviewer** op de omgeving `github-pages` | Weinig git-ceremonie voor één persoon; "build once, promote" |
| B6 | Prod stapt over van legacy naar publiceren via Actions (`actions/deploy-pages`) | Alleen zo kan prod achter de goedkeuring en hetzelfde artifact gebruiken |
| B7 | Staging krijgt een **omhulsel**: `CNAME`, `noindex`, analytics eruit. Prod krijgt de build onaangeroerd | Eén build voor beide; omgevingsverschillen alleen bij de deploy |
| B8 | `noindex` via `<meta>`, geen `robots.txt: Disallow` | Google moet kunnen crawlen om de noindex te zien |
| B9 | Toegang tot `site-staging` via een **deploy key** met schrijfrecht | Beperkt tot één repo; veiliger dan een persoonlijk token |
| B10 | `site-staging` krijgt per deploy één verse commit (force-push) | Voorkomt dat de repo bij elke deploy de afbeeldingen opnieuw aan geschiedenis toevoegt |

## 4. Architectuur

```
                   businessdatasolutions/site  (bron, branch master)
                                  │
                          GitHub Actions: deploy.yml
              ┌───────────────────┴────────────────────┐
           build  ──►  linkcheck  ──►  artifact (_site/)
              │                                        │
   automatisch (push master of                 alleen master,
   handmatig op elke branch)                   na Approve van Witek
              ▼                                        ▼
   staging-omhulsel toepassen                  actions/deploy-pages
   push naar site-staging (main)               omgeving: github-pages
              ▼                                        ▼
   https://staging.businessdatasolutions.nl    https://www.businessdatasolutions.nl
```

## 5. Componenten

### 5.1 In `site`

| Bestand | Verantwoordelijkheid |
|---|---|
| `.github/workflows/deploy.yml` | Triggers, jobs, rechten, omgevingen |
| `scripts/build.sh` | Kopieert de publiceerbare bestanden naar `_site/`. Enige plek waar het redesign later een echte build-stap inhangt |
| `scripts/staging-envelope.sh <dir> <host>` | Past het staging-omhulsel toe op een uitgepakte build. Lokaal los te draaien en te testen |
| `index.html` | Krijgt markeringen `<!-- analytics:start -->` en `<!-- analytics:end -->` rond het Hotjar-blok |
| `README.md` | Nieuwe sectie "Deployen" (hoe staging en prod werken, hoe goed te keuren, hoe terug te draaien) |

**`build.sh`** neemt mee: `index.html`, `styles.css`, `blog/`, `images/`, plus eventuele toekomstige publieke bestanden die expliciet worden toegevoegd (allowlist, geen denylist). Niet mee: `README.md`, `CNAME`, `docs/`, `scripts/`, `.github/`. Een allowlist zorgt dat een nieuw intern bestand nooit per ongeluk publiek wordt.

**`staging-envelope.sh`** doet drie dingen, in deze volgorde:

1. In elk `.html`-bestand: alles tussen `<!-- analytics:start -->` en `<!-- analytics:end -->` verwijderen (markeringen inbegrepen).
2. In elk `.html`-bestand: `<meta name="robots" content="noindex, nofollow">` direct vóór `</head>` invoegen.
3. Een bestand `CNAME` met `<host>` schrijven in de root.

Het script faalt (exit ≠ 0) als een `.html`-bestand geen `</head>` heeft of als er een `analytics:start` zonder bijbehorende `analytics:end` staat. Zo valt een stille mislukking op in plaats van dat staging ongemerkt toch geïndexeerd wordt.

### 5.2 Repo `site-staging`

- Publiek, beschrijving: "Staging-hosting voor businessdatasolutions/site. Niet handmatig bewerken: elke deploy overschrijft deze repo."
- Pages: bron branch `main` / root, custom domain `staging.businessdatasolutions.nl`, HTTPS afdwingen zodra het certificaat er is.
- Deploy key (schrijfrecht) met titel `deploy from site`.

### 5.3 GitHub-omgevingen in `site`

| Omgeving | Beveiliging | Secrets |
|---|---|---|
| `staging` | geen goedkeuring | `STAGING_DEPLOY_KEY` (privé-deel van de deploy key) |
| `github-pages` | verplichte reviewer: `witusj` (zelfgoedkeuring toegestaan); deploy-branchregel: alleen `master` | geen |

Het privé-deel van de deploy key staat na het aanmaken alleen nog in het secret; de lokale kopie wordt verwijderd.

## 6. Workflow `deploy.yml`

### 6.1 Triggers

| Gebeurtenis | build + linkcheck | staging | prod |
|---|---|---|---|
| `push` naar `master` | ✓ | ✓ automatisch | ✓ na Approve |
| `workflow_dispatch` op een andere branch | ✓ | ✓ | – |
| `workflow_dispatch` op `master` | ✓ | ✓ | ✓ na Approve |
| `pull_request` naar `master` | ✓ | – | – |

`workflow_dispatch` werkt pas zodra `deploy.yml` op de standaardbranch (`master`) staat. Daarom heeft de workflow tijdens de overstap een **tijdelijke** extra trigger: `push` naar `ci/pipeline` (zie §8). Die gedraagt zich als een handmatige run op een niet-`master`-branch: build + staging, geen prod.

### 6.2 Jobs

1. **`build`**
   - `scripts/build.sh` → `_site/`
   - Linkcheck met lychee op `_site/`, offline (alleen interne links), root-relatieve links opgelost tegen `_site/`, ankers (`#contact`) gecontroleerd. Een kapotte interne link laat de job falen.
   - `_site/` uploaden als Pages-artifact.
2. **`deploy-staging`** (niet bij `pull_request`; omgeving `staging`)
   - Artifact downloaden en uitpakken.
   - `scripts/staging-envelope.sh _site staging.businessdatasolutions.nl`
   - Force-push van één verse commit naar `site-staging` / `main` via `STAGING_DEPLOY_KEY`.
   - Concurrency-groep `staging`, een lopende oudere deploy wordt afgebroken.
3. **`deploy-production`** (alleen als `github.ref == refs/heads/master`, na `deploy-staging`; omgeving `github-pages`)
   - Wacht op goedkeuring via de omgeving.
   - `actions/deploy-pages` publiceert het artifact uit `build`, ongewijzigd.
   - Concurrency-groep `production`, nooit afbreken tijdens een lopende deploy.

### 6.3 Rechten

Standaard voor de workflow: `contents: read`. Alleen `deploy-production` krijgt `pages: write` en `id-token: write`. `STAGING_DEPLOY_KEY` is een omgevingssecret en dus alleen beschikbaar voor `deploy-staging`.

### 6.4 Werken met het redesign

Het redesign leeft op een eigen branch (bijv. `redesign`). Op staging zetten gaat met "Run workflow" in de Actions-tab of `gh workflow run deploy.yml --ref redesign`. Er is één staging-plek: de laatste deploy wint. Een push naar `master` (bijv. een blogpost) overschrijft dus een redesign-preview op staging; opnieuw draaien op `redesign` zet die terug.

## 7. Handwerk bij Mijndomein (Witek)

| Prioriteit | Record | Waarde | Effect |
|---|---|---|---|
| Nodig | `CNAME staging` | `businessdatasolutions.github.io.` | Staging bereikbaar |
| Aanbevolen | `A @` (vervangt 213.249.67.10) | `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` | `businessdatasolutions.nl` stuurt door naar `www` |
| Aanbevolen | `TXT _github-pages-challenge-businessdatasolutions` | waarde uit Organisatie-instellingen → Pages → Add a domain | Domein geverifieerd; niemand anders kan subdomeinen op GitHub Pages claimen |

Bij het A-record: eerst controleren of Mijndomein op het kale domein een URL-doorsturing heeft ingesteld; die moet dan uit.

## 8. Overstap (volgorde)

Alle wijzigingen staan op branch `ci/pipeline` tot stap 6. Zolang Pages in legacy-modus vanaf `master` publiceert, raakt dit de live site niet.

1. Op `ci/pipeline`: `build.sh`, `staging-envelope.sh`, `deploy.yml` (met de tijdelijke trigger `push` naar `ci/pipeline`), markeringen in `index.html`, README-sectie.
2. `site-staging` aanmaken; deploy key aanmaken en koppelen; omgeving `staging` met secret.
3. Witek zet het `CNAME staging`-record (en eventueel de aanbevolen records).
4. `ci/pipeline` pushen → de workflow draait via de tijdelijke trigger → staging komt op; prod-job wordt overgeslagen. Pages-instellingen van `site-staging` zetten (custom domain, HTTPS). Acceptatiecriteria A2 en A3 controleren.
5. Omgeving `github-pages` beveiligen (reviewer + branchregel). Pages van `site` omzetten naar `build_type: workflow`. De huidige deployment blijft online.
6. Tijdelijke trigger uit `deploy.yml` halen, `ci/pipeline` mergen naar `master` → staging werkt bij, prod wacht → Witek keurt goed → A4 controleren. Daarna A2 opnieuw controleren met een echte `workflow_dispatch` op een testbranch.

## 9. Terugdraaien

| Situatie | Actie | Duur |
|---|---|---|
| Inhoudelijke fout op prod | `git revert` + push → staging controleren → Approve | minuten |
| Pijplijn kapot, prod moet nu iets anders tonen | Pages terug naar legacy: `gh api -X PUT repos/businessdatasolutions/site/pages -f build_type=legacy -f "source[branch]=master" -f "source[path]=/"` | één commando; daarna publiceert `master` direct, zoals voorheen |

Bij terugval naar legacy publiceert Jekyll `master` inclusief `docs/` en `scripts/`. Dat is acceptabel als noodgreep, niet als blijvende toestand.

## 10. Acceptatiecriteria

| # | Criterium | Verificatie |
|---|---|---|
| A1 | Een PR met een kapotte interne link geeft een rode check en deployt niets | Test-PR met een link naar `/bestaat-niet/` |
| A2 | Een run op een niet-`master`-branch werkt staging bij; `deploy-production` staat op *skipped* | Run-overzicht in Actions: eerst via de tijdelijke trigger (§8 stap 4), na de merge met een echte `workflow_dispatch` op een testbranch (§8 stap 6) |
| A3 | `https://staging.businessdatasolutions.nl` geeft 200 met geldig certificaat; elke HTML-pagina bevat de noindex-meta; geen `hotjar` in de broncode; blognavigatie werkt | `curl` op `/`, `/blog/` en beide posts; klikken door de navigatie |
| A4 | Na een push naar `master` staat `deploy-production` op *Waiting for review*; na Approve toont `www` de nieuwe versie met HTTPS en **zonder** noindex; Hotjar staat er nog | `curl` op `www` (rekening houden met ± 10 minuten CDN-cache) |
| A5 | `staging-envelope.sh` faalt op een HTML-bestand zonder `</head>` en op een `analytics:start` zonder `analytics:end` | Lokaal draaien op een testmap |
| A6 | (Als het A-record is aangepast) `https://businessdatasolutions.nl` stuurt door naar `https://www.businessdatasolutions.nl` | `curl -I` |

## 11. Buiten scope

- Het redesign zelf, inclusief de keuze voor een eventuele static-site-generator.
- Preview-omgevingen per pull request.
- Lighthouse-, toegankelijkheids- of HTML-validatiechecks (horen bij het redesign).
- `master` hernoemen naar `main`.
- Besluit of Hotjar blijft (het omhulsel werkt voor elk analytics-blok tussen de markeringen).

## 12. Risico's en aandachtspunten

- **Repo privé maken schakelt de knop uit.** Verplichte reviewers werken op het gratis plan alleen voor publieke repo's. Wordt `site` privé, dan gaat prod zonder goedkeuring live. Dit staat ook in de README.
- **Eén staging-plek.** Redesign-previews en `master`-pushes overschrijven elkaar (zie 6.4).
- **Certificaat voor staging.** GitHub geeft het certificaat pas uit als de DNS klopt; dat kan van enkele minuten tot een paar uur duren. HTTPS afdwingen gebeurt daarna.
- **Wildcard-DNS.** Als Mijndomein een wildcard-record heeft, blijven willekeurige subdomeinen naar 213.249.67.10 wijzen. Geen probleem voor deze pijplijn, wel iets om op te ruimen.
- **CDN-cache.** Pages cachet tot ± 10 minuten. Direct na een deploy kan de oude versie nog zichtbaar zijn.
- **Deploy key roteren.** Een gelekte sleutel geeft alleen schrijfrecht op `site-staging`. Roteren: nieuwe sleutel aanmaken, secret vervangen, oude verwijderen.
