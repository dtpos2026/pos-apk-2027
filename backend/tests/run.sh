#!/bin/sh
# Applies the migration to a scratch database on a local Postgres and runs the tests.
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
DB=dtfood_test
su postgres -c "dropdb --if-exists $DB; createdb $DB"
for f in tests/auth_stub.sql supabase/migrations/0001_dtfood.sql tests/0001_dtfood_test.sql; do
  su postgres -c "psql -v ON_ERROR_STOP=1 -q -d $DB -f $DIR/$f" | grep -v '^\s*$' | grep -E 'PASSED|ERROR' || true
done
