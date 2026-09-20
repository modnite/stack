#!/bin/sh
# Copies the backup folder to remote storage once a day (rclone "copy" never deletes what is already there,
# so an accident on this server cannot erase the off-site copies). Prune the remote with its own lifecycle rule.
set -u

if [ -z "${RCLONE_REMOTE:-}" ]; then
  echo "offsite: RCLONE_REMOTE is not set in .env, nothing to do." >&2
  sleep 3600
  exit 1
fi

while true; do
  # Give the backup job time to finish its nightly run first.
  sleep 600
  if rclone copy /backups "offsite:${RCLONE_REMOTE}" --transfers 2 --stats-one-line; then
    echo "offsite: copied to ${RCLONE_REMOTE}"
  else
    echo "offsite: copy FAILED" >&2
  fi
  sleep 86400
done
