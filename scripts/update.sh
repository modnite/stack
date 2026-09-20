#!/usr/bin/env bash
# Update the stack: pull new images, restart what changed, check it came up, and clean up.
#
#   ./scripts/update.sh                     pull whatever the tags in .env point to and apply it
#   ./scripts/update.sh thrice=1.4.0        deploy THRICE version 1.4.0 (records the old tags first)
#   ./scripts/update.sh site=sha-3f9c2ab    deploy one commit of the website
#   ./scripts/update.sh thrice=1.4.0 site=0.9.1
#   ./scripts/update.sh rollback            go back to the tags used before the last version change
#
# Pin versions in .env (THRICE_TAG=1.4.0) for production so an update is a deliberate act and a rollback is one command.
# With floating tags such as "latest" or "main" an update still works, but rollback needs the previous version number.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "No .env here. Copy .env.example to .env and fill it in first." >&2; exit 1; }

set_tag() { # KEY VALUE
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else printf '%s=%s\n' "$1" "$2" >> .env; fi
}

changed=0
case "${1:-}" in
  rollback)
    [ -f .env.previous ] || { echo "Nothing to roll back to: no .env.previous." >&2; exit 1; }
    cp .env.previous .env
    echo "Restored the previous tags."
    ;;
  *)
    for arg in "$@"; do
      case "$arg" in
        thrice=*|site=*) ;;
        *) echo "Unknown argument: $arg (use thrice=TAG, site=TAG or rollback)" >&2; exit 1 ;;
      esac
    done
    if [ "$#" -gt 0 ]; then
      cp .env .env.previous
      for arg in "$@"; do
        case "$arg" in
          thrice=*) set_tag THRICE_TAG "${arg#thrice=}" ;;
          site=*) set_tag SITE_TAG "${arg#site=}" ;;
        esac
      done
      changed=1
    fi
    ;;
esac

# Keep this stack's own files current when it is a git checkout with nothing edited locally.
if [ -d .git ] && [ -z "$(git status --porcelain --untracked-files=no)" ] && git remote get-url origin >/dev/null 2>&1; then
  git pull --ff-only || echo "Could not fast-forward the stack files; continuing with what is here."
fi

docker compose pull
docker compose up -d --remove-orphans

wait_healthy() { # SERVICE
  local id status
  for _ in $(seq 1 60); do
    id="$(docker compose ps -q "$1" 2>/dev/null || true)"
    if [ -n "$id" ]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id")"
      case "$status" in
        healthy|running) return 0 ;;
        unhealthy|exited|dead) return 1 ;;
      esac
    fi
    sleep 3
  done
  return 1
}

failed=0
for svc in thrice-app site-app caddy; do
  if wait_healthy "$svc"; then echo "ok: $svc"; else echo "NOT HEALTHY: $svc" >&2; docker compose logs --tail 30 "$svc" >&2 || true; failed=1; fi
done

if [ "$failed" = 1 ]; then
  if [ "$changed" = 1 ] && [ -f .env.previous ]; then
    echo "Something did not come up. Rolling back to the previous tags." >&2
    cp .env.previous .env
    docker compose up -d --remove-orphans
  else
    echo "Something did not come up. Check the logs above. To go back, use: ./scripts/update.sh rollback (after a tagged update)." >&2
  fi
  exit 1
fi

docker image prune -f >/dev/null
echo "Done."
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
