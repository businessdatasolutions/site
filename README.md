# Ten Hove | Business Data Solutions — Website

De officiële website van Business Data Solutions / Ten Hove, een advies- en onderwijsbedrijf dat organisaties helpt om data voor hen te laten werken.

## Doel

Deze repository bevat de broncode van de marketingwebsite van **Business Data Solutions** (handelsnaam: Ten Hove). De site presenteert de diensten, expertise en contactmogelijkheden van het bedrijf aan potentiële klanten en samenwerkingspartners.

## Inhoud

- **Homepage**: Hoofdpagina met hero-sectie, dienstaanbod en call-to-action.
- **Branding**: Logo's en huisstijlelementen van het Ten Hove / Business Data Solutions merk.
- **Contactmogelijkheden**: Directe contactinformatie voor zakelijke vragen.

## Technologie

De website is gebouwd als een enkelvoudige statische HTML/CSS-pagina en is gehost via GitHub Pages op het eigen domein [www.businessdatasolutions.nl](https://www.businessdatasolutions.nl).

## Live Website

Bezoek de website op: [www.businessdatasolutions.nl](https://www.businessdatasolutions.nl/)

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
- Wacht er al een run op goedkeuring, dan staat een nieuwere run daarachter in de rij. Is er inmiddels nieuwer werk, wijs dan de oudste af: de nieuwste schuift door en vraagt opnieuw om goedkeuring. Een derde run annuleert de middelste, zodat altijd de nieuwste overblijft.
- Werk nooit in `businessdatasolutions/site-staging`: elke deploy overschrijft die repo.
