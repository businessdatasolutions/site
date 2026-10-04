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
