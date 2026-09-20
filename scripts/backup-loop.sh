#!/bin/sh
# Dumps every database and the website's uploads on a schedule, and prunes old copies.
# Each file is written under a temporary name and renamed only when complete, so a failed run never leaves a
# truncated backup behind.
set -u

while true; do
  stamp=$(date +%Y%m%d-%H%M%S)
  ok=1
  for db in thrice studio; do
    if pg_dump -d "$db" -f "/backups/$db-$stamp.sql.tmp" && mv "/backups/$db-$stamp.sql.tmp" "/backups/$db-$stamp.sql" && gzip -f "/backups/$db-$stamp.sql"; then
      :
    else
      ok=0
    fi
  done
  if tar -czf "/backups/media-$stamp.tar.gz.tmp" -C /media . && mv "/backups/media-$stamp.tar.gz.tmp" "/backups/media-$stamp.tar.gz"; then
    :
  else
    ok=0
  fi

  if [ "$ok" = 1 ]; then
    echo "backup written: $stamp"
  else
    rm -f /backups/*.tmp
    echo "backup FAILED" >&2
  fi

  find /backups \( -name '*.sql.gz' -o -name 'media-*.tar.gz' \) -mtime +"${BACKUP_KEEP_DAYS:-14}" -delete
  sleep $((${BACKUP_INTERVAL_HOURS:-24} * 3600))
done
