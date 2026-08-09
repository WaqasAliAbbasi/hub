#!/bin/sh
# Nightly backup: every /srv/<project>/data/ to Spaces via restic, plus a logical
# pg_dump of any running Postgres first (a live data directory risks a torn restore).
set -eu

cd /srv/platform/backup

# Written at 0600 by `make sync`, which decrypts secrets.enc.env on your laptop.
set -a
. ./.env
set +a

restic snapshots >/dev/null 2>&1 || restic init

for cid in $(docker ps -q); do
  image=$(docker inspect -f '{{.Config.Image}}' "$cid")
  case "$image" in
    postgres:*|*/postgres:*)
      name=$(docker inspect -f '{{.Name}}' "$cid" | tr -d /)
      dumpdir="/srv/platform/backup/pg-dumps/$name"
      mkdir -p "$dumpdir"
      docker exec "$cid" sh -c 'pg_dumpall -U "$POSTGRES_USER"' > "$dumpdir/dump.sql"
      ;;
  esac
done

for dir in /srv/*/data /srv/platform/backup/pg-dumps; do
  [ -d "$dir" ] || continue
  restic backup "$dir" --tag "$(basename "$(dirname "$dir")")"
done

restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune

date -u +%Y-%m-%dT%H:%M:%SZ > /srv/platform/backup/last-success
