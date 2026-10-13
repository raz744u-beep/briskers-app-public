#!/usr/bin/env bash
# CI-only disposable Docker service; intentionally accepts no external DB URL.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${CLEANUP_TEST_CONTAINER:?Supply the isolated GitHub Actions PostgreSQL service ID}"
image=$(docker inspect --format '{{.Config.Image}}' "$CLEANUP_TEST_CONTAINER")
if [[ "$image" != 'postgres:17.11-bookworm' ]]; then
  echo "Refusing unexpected test service image: $image" >&2
  exit 1
fi
psql_db() { docker exec -i "$CLEANUP_TEST_CONTAINER" psql -X -U postgres -v ON_ERROR_STOP=1 -d "$1" "${@:2}"; }
psql_db postgres -c 'CREATE DATABASE cleanup_functional;'
psql_db postgres -c 'CREATE DATABASE cleanup_races;'
for db in cleanup_functional cleanup_races; do
  psql_db "$db" < tools/tests/test_job_cleanup_schema.sql
  psql_db "$db" < supabase/migrations/20261013001224_owner_test_job_cleanup_v1.sql
done
psql_db cleanup_functional < tools/tests/test_job_cleanup_cases.sql
psql_db cleanup_functional < tools/tests/test_job_cleanup_isolation.sql
psql_db cleanup_functional < tools/tests/test_job_cleanup_registry_cases.sql
psql_db cleanup_functional < tools/tests/test_job_cleanup_native_budget.sql
psql_db cleanup_races < tools/tests/test_job_cleanup_race_setup.sql
run_pair() {
  local first=$1 second=$2 a b a_status=0 b_status=0
  psql_db cleanup_races < "$first" & a=$!
  psql_db cleanup_races < "$second" & b=$!
  wait "$a" || a_status=$?
  wait "$b" || b_status=$?
  if [[ $a_status != 0 || $b_status != 0 ]]; then
    echo "Concurrent test failed: $first ($a_status), $second ($b_status)" >&2
    return 1
  fi
}
run_pair tools/tests/test_job_cleanup_payment_race_a.sql tools/tests/test_job_cleanup_payment_race_b.sql
run_pair tools/tests/test_job_cleanup_snapshot_race_a.sql tools/tests/test_job_cleanup_snapshot_race_b.sql
psql_db cleanup_races -c "DO \$\$ BEGIN IF EXISTS(SELECT 1 FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000001') OR (SELECT count(*) FROM briskers_cleanup_private.audit)<>1 OR (SELECT count(*) FROM briskers_cleanup_private.tombstones)<>3 THEN RAISE EXCEPTION 'Stale snapshot race left invalid final state'; END IF; END \$\$;"
echo 'PASS native PostgreSQL functional, permissions, timeout rollback, payment race and stale-snapshot replay tests'
