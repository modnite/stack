#!/usr/bin/env bash
# Restore one database from a backup file. This REPLACES the database's current contents.
#
#   ./scripts/restore.sh thrice   thrice-20260919-020000.sql.gz
#   ./scripts/restore.sh studio studio-20260919-020000.sql.gz
#
# Files are read from the backups volume. To restore from an off-site copy, put the file in that volume first.
set -euo pipefail
cd "$(dirname "$0")/.."

db="${1:-}"
file="${2:-}"
case "$db" in thrice|studio) ;; *) echo "Usage: $0 <thrice|studio> <backup-file.sql.gz>" >&2; exit 1 ;; esac
[ -n "$file" ] || { echo "Say which backup file to restore." >&2; exit 1; }

app=thrice-app; [ "$db" = studio ] && app=site-app
echo "This will erase the current '$db' database and replace it with $file."
read -r -p "Type the database name to continue: " answer
[ "$answer" = "$db" ] || { echo "Cancelled."; exit 1; }

docker compose stop "$app" $([ "$db" = thrice ] && echo thrice-worker) >/dev/null
docker compose run --rm --no-deps -T -e PGHOST=postgres -e PGUSER=postgres -e PGPASSWORD="$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)" \
  --entrypoint sh backup -c "
    set -e
    psql -d postgres -v ON_ERROR_STOP=1 -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db' AND pid <> pg_backend_pid()\" >/dev/null
    dropdb --if-exists $db
    createdb -O $db $db
    gunzip -c /backups/$file | psql -d $db -v ON_ERROR_STOP=1 -q
  "
docker compose up -d
echo "Restored $db from $file."
