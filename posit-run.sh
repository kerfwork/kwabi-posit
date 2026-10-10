#!/usr/bin/env bash
# posit<16,1> through the kwabi runtime, on PostgreSQL: the install and bind scripts, the
# behaviour checks, and the sensor-readings demo (sql/demo.sql).
#
#   RUNTIME_BUNDLE=<kwabi_runtime_pgNN.<dl>> SCRATCH=<dir> ./posit-run.sh <major>
#
# The runtime bundle comes from kerfwork/kwabi-runtime (make build PG=<major>). Optional:
# PGBIN (the PostgreSQL bin directory), DLSUFFIX, POSIT_PORT.
set -euo pipefail
cd "$(dirname "$0")"
major="${1:?major}"
: "${SCRATCH:?set SCRATCH}"
: "${RUNTIME_BUNDLE:?set RUNTIME_BUNDLE to the runtime bundle for this major}"

bin="${PGBIN:-/opt/homebrew/opt/postgresql@$major/bin}"
dl="${DLSUFFIX:-dylib}"
port="${POSIT_PORT:-$((5970 + major))}"
data="$SCRATCH/posit-pg$major"
body="$PWD/build/libkwabi_posit16_1.$dl"
fail=0

check() {
  if [ "$2" = "$3" ]; then echo "  PASS $1 ($3)"; else echo "  FAIL $1: want '$2' got '$3'"; fail=1; fi
}

make -s lib
"$bin/pg_ctl" -D "$data" -m fast stop >/dev/null 2>&1 || true
rm -rf "$data"
"$bin/initdb" -D "$data" -U postgres -A trust >"$SCRATCH/posit-initdb-$major.log" 2>&1
cat >> "$data/postgresql.conf" <<CONF
port = $port
listen_addresses = '127.0.0.1'
unix_socket_directories = ''
shared_preload_libraries = '$RUNTIME_BUNDLE'
CONF
"$bin/pg_ctl" -D "$data" -l "$SCRATCH/posit-server-$major.log" -w start >/dev/null
trap '"$bin/pg_ctl" -D "$data" -m fast stop >/dev/null 2>&1 || true' EXIT

PSQL=("$bin/psql" -X -q -At -h 127.0.0.1 -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1)
Q() { "${PSQL[@]}" -c "$1" 2>>"$SCRATCH/posit-$major.stderr"; }
# An error's SQLSTATE, or "ok": the statement's value is not needed.
STATE() {
  "${PSQL[@]}" -c "DO \$\$ BEGIN EXECUTE \$q\$$1\$q\$; RAISE NOTICE 'state=ok'; EXCEPTION WHEN others THEN RAISE NOTICE 'state=%', SQLSTATE; END \$\$;" 2>&1 \
    | sed -n 's/.*state=//p'
}

# The type, then the body. Both scripts take the bundle paths as variables.
"${PSQL[@]}" -v runtime="$RUNTIME_BUNDLE" -f sql/install.sql >/dev/null
check "bind the body" "bound" "$("${PSQL[@]}" -v runtime="$RUNTIME_BUNDLE" -v body="$body" -f sql/bind.sql | head -1)"

check "1 prints as 1" "1" "$(Q "SELECT '1'::posit16_1::text")"
check "0.5 prints as 0.5" "0.5" "$(Q "SELECT '0.5'::posit16_1::text")"
check "a whole number prints without an exponent" "1024" "$(Q "SELECT '1024'::posit16_1::text")"
check "a value that is not a decimal is 22P02" "22P02" "$(STATE "SELECT 'x'::posit16_1")"
check "control: a decimal is not an error" "ok" "$(STATE "SELECT '2.5'::posit16_1")"

Q "CREATE TABLE tp (id int, v posit16_1)" >/dev/null
Q "INSERT INTO tp VALUES (1, '3'), (2, '0.25'), (3, '-2')" >/dev/null
check "stored values read back" "3|0.25|-2" "$(Q "SELECT string_agg(v::text, '|' ORDER BY id) FROM tp")"

check "eq" "t" "$(Q "SELECT '2'::posit16_1 = '2'::posit16_1")"
check "control: unequal is false" "f" "$(Q "SELECT '2'::posit16_1 = '3'::posit16_1")"
check "lt" "t" "$(Q "SELECT '1'::posit16_1 < '2'::posit16_1")"
check "control: reversed lt is false" "f" "$(Q "SELECT '2'::posit16_1 < '1'::posit16_1")"
check "ge at equality" "t" "$(Q "SELECT '4'::posit16_1 >= '4'::posit16_1")"
check "negative below positive" "t" "$(Q "SELECT '-2'::posit16_1 < '0.25'::posit16_1")"

check "add" "3" "$(Q "SELECT ('1'::posit16_1 + '2'::posit16_1)::text")"
check "sub" "2" "$(Q "SELECT ('3'::posit16_1 - '1'::posit16_1)::text")"
check "mul" "4" "$(Q "SELECT ('2'::posit16_1 * '2'::posit16_1)::text")"
check "div" "1.5" "$(Q "SELECT ('3'::posit16_1 / '2'::posit16_1)::text")"
check "division by zero is 22012" "22012" "$(STATE "SELECT '3'::posit16_1 / '0'::posit16_1")"
check "control: division by one is fine" "ok" "$(STATE "SELECT '3'::posit16_1 / '1'::posit16_1")"
check "overflow saturates, it is not an error" "ok" "$(STATE "SELECT '1e30'::posit16_1 * '1e30'::posit16_1")"

Q "CREATE INDEX tp_v ON tp (v)" >/dev/null
check "ORDER BY uses cmp" "-2|0.25|3" "$(Q "SELECT string_agg(v::text, '|' ORDER BY v) FROM tp")"
check "btree index serves equality" "Index" \
  "$(Q "SET enable_seqscan = off; EXPLAIN (COSTS OFF) SELECT v FROM tp WHERE v = '3'" | grep -o 'Index' | head -1)"

check "a missing body path is refused at bind" "bind refused" \
  "$(Q "SELECT kwabi_hook_test_bind('posit16_1', '$SCRATCH/missing.dylib')")"

"${PSQL[@]}" -v runtime="$RUNTIME_BUNDLE" -f sql/aggregates.sql >/dev/null
check "sum, max and min over the table" "1.25|3|-2" "$(Q "SELECT sum(v)::text || '|' || max(v)::text || '|' || min(v)::text FROM tp")"
check "avg of an empty set is NULL" "NULL" "$(Q "SELECT coalesce(avg(v)::text, 'NULL') FROM tp WHERE id > 99")"

# The demo application, in a fresh schema so its tables do not clash with the checks above.
demo_out="$SCRATCH/posit-demo-$major.out"
"${PSQL[@]}" -c "CREATE SCHEMA demo; SET search_path = demo, public;" >/dev/null
"${PSQL[@]}" -c "SET search_path = demo, public;" -f sql/demo.sql > "$demo_out" 2>&1 \
  || { echo "  FAIL demo ran with an error:"; cat "$demo_out"; fail=1; }
check "demo: the highest raw reading is 8 at site 2" "2|0|8" \
  "$(awk '/== 1\./ {getline; print; exit}' "$demo_out")"
check "demo: north summary (sum, avg, max, min of calibrated readings)" "north|14.625|3.6562|4.5|3" \
  "$(sed -n '/== 7\./,$p' "$demo_out" | grep -E '^north\|' | head -1)"
check "demo: south summary" "south|13.875|3.4688|4|3" \
  "$(sed -n '/== 7\./,$p' "$demo_out" | grep -E '^south\|' | head -1)"
check "demo: the posit sum loses the 1; the float sum keeps it" "983040|983040|1000001" \
  "$(sed -n '/== 6\./,$p' "$demo_out" | grep -E '^983040\|' | head -1)"

if [ "$fail" -eq 0 ]; then echo "posit16_1 passed (PG $major)"; else echo "FAILURES (PG $major)"; exit 1; fi
