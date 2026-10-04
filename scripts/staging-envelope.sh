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
