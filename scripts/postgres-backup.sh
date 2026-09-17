#!/bin/sh
# Periodic logical backup of the homelab Postgres database.
#
# Runs as the entrypoint of the `postgres-backup` compose service. It writes a
# custom-format pg_dump into $BACKUP_DIR (the `pgbackups` volume) on an
# interval, then prunes dumps older than $BACKUP_RETENTION_DAYS.
#
# Restore a dump with:
#   pg_restore --clean --if-exists --no-owner -d "$PGDATABASE" <dump-file>
set -eu

: "${PGHOST:=postgres}"
: "${PGDATABASE:=app}"
: "${PGUSER:=app}"
: "${BACKUP_DIR:=/backups}"
: "${BACKUP_INTERVAL_SECONDS:=86400}"
: "${BACKUP_RETENTION_DAYS:=7}"

mkdir -p "$BACKUP_DIR"

while true; do
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  dump_file="$BACKUP_DIR/${PGDATABASE}-${timestamp}.dump"

  echo "[backup] dumping ${PGDATABASE} to ${dump_file}"
  if pg_dump --no-owner --format=custom --file="$dump_file"; then
    echo "[backup] wrote ${dump_file}"
  else
    echo "[backup] pg_dump failed" >&2
  fi

  find "$BACKUP_DIR" -type f -name '*.dump' -mtime "+${BACKUP_RETENTION_DAYS}" -delete
  sleep "$BACKUP_INTERVAL_SECONDS"
done
