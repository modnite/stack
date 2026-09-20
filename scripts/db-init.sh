#!/bin/sh
# Creates one database and one login per app, and keeps the passwords in step with .env.
# Safe to run on every start, on a brand-new server or an existing volume.
set -eu

ensure() {
  name="$1"
  password="$2"
  if [ -z "$password" ]; then
    echo "[db-init] no password given for $name" >&2
    exit 1
  fi
  psql -v ON_ERROR_STOP=1 -v name="$name" -v pw="$password" -d postgres <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'name', :'pw')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'name')
\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'name', :'pw')
\gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'name', :'name')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'name')
\gexec
SQL
  echo "[db-init] $name ready"
}

ensure thrice "$THRICE_DB_PASSWORD"
ensure studio "$SITE_DB_PASSWORD"
