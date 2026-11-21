#!/usr/bin/env bash
set -euo pipefail
# A dedicated ephemeral Postgres service is required. No DATABASE_URL is used.
if [[ "${ACK_SYNTHETIC_POSTGRES:-}" != "1" ]]; then
  echo 'Set ACK_SYNTHETIC_POSTGRES=1 only for a disposable local test cluster.' >&2
  exit 2
fi
host="${OWNER_GUARD_PGHOST:-127.0.0.1}"
case "$host" in 127.0.0.1|localhost|::1) ;; *) echo 'Only loopback PostgreSQL hosts are allowed.' >&2; exit 2 ;; esac
command -v psql >/dev/null || { echo 'psql is required.' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 is required.' >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prevent libpq service/host-address overrides from selecting a hosted server.
unset PGSERVICE PGSERVICEFILE PGHOST PGHOSTADDR PGDATABASE PGUSER PGPORT PGOPTIONS
python3 "$root/assemble.py" | psql -X --no-password --set=ON_ERROR_STOP=1 \
  --host="$host" --port="${OWNER_GUARD_PGPORT:-5432}" \
  --username="${OWNER_GUARD_PGUSER:-postgres}" \
  --dbname=briskers_owner_guard_synthetic
