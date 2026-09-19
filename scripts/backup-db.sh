#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/opt/ghost/.env"
DUMP_DIR="/opt/ghost/backups"
DUMP_FILE="${DUMP_DIR}/ghost-db.sql.gz"

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

mkdir -p "$DUMP_DIR"

notify_failure() {
  local message="$1"
  # Guarded explicitly rather than relying on `|| true` alone: under
  # set -u, an unset NTFY_TOPIC would abort the script on variable
  # expansion, before curl ever runs, silently skipping the one thing
  # this function exists to do. A logged skip beats a silent crash.
  if [[ -z "${NTFY_TOPIC:-}" ]]; then
    echo "NTFY_TOPIC is not set, cannot send failure notification: $message" >&2
    return 0
  fi
  # Best-effort beyond this point: a failed notification must never mask
  # the real failure, so curl's own exit code is discarded.
  curl -fsS \
    -H "Title: Ghost DB backup failed" \
    -H "Priority: high" \
    -d "$message" \
    "https://ntfy.sh/${NTFY_TOPIC}" || true
}

# --single-transaction takes a consistent InnoDB snapshot without locking
# tables, so this runs against the live database without blocking Ghost.
if docker exec ghost-db-1 mysqldump \
    -u root -p"${DATABASE_ROOT_PASSWORD}" \
    --single-transaction --quick --routines --triggers \
    ghost | gzip > "${DUMP_FILE}.tmp"; then
  # Atomic rename: a reader (or vzdump, snapshotting mid-write) never sees
  # a half-written dump file under the real name.
  mv "${DUMP_FILE}.tmp" "$DUMP_FILE"
else
  rm -f "${DUMP_FILE}.tmp"
  notify_failure "mysqldump failed on $(hostname) at $(date -u +%FT%TZ)"
  exit 1
fi
