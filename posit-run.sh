#!/usr/bin/env bash
# posit<16,1> through the kwabi runtime, on PostgreSQL.
#
#   RUNTIME_BUNDLE=<path to kwabi_runtime_pgNN.<dl>> SCRATCH=<dir> ./posit-run.sh <major>
#
# The runtime bundle comes from kerfwork/kwabi-runtime (make build PG=<major>). This script
# builds the body (make lib), starts a preloaded cluster, creates the type through the
# runtime's generic I/O and operator functions, binds the body, and checks behaviour.
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

Q() { "$bin/psql" -X -q -At -h 127.0.0.1 -p $port -U postgres -d postgres -c "$1" 2>>"$SCRATCH/posit-$major.stderr"; }
# An error's SQLSTATE, or "ok": the statement's value is not needed.
STATE() {
  "$bin/psql" -X -q -At -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "DO \$\$ BEGIN EXECUTE \$q\$$1\$q\$; RAISE NOTICE 'state=ok'; EXCEPTION WHEN others THEN RAISE NOTICE 'state=%', SQLSTATE; END \$\$;" 2>&1 \
    | sed -n 's/.*state=//p'
}

# The runtime's generic functions, the type, and the bind. A name's functions end in _in,
# _out, or an operator suffix; the binding is the part before the last underscore.
ops_sql=""
for f in "eq:boolean" "ne:boolean" "lt:boolean" "le:boolean" "gt:boolean" "ge:boolean" \
         "add:posit16_1" "sub:posit16_1" "mul:posit16_1" "div:posit16_1" "cmp:int4"; do
  op=${f%%:*}; ret=${f##*:}
  ops_sql+="CREATE FUNCTION posit16_1_$op(posit16_1, posit16_1) RETURNS $ret AS '$RUNTIME_BUNDLE', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;"$'\n'
done
"$bin/psql" -X -q -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 <<SQL
CREATE FUNCTION kwabi_hook_test_bind(text, text) RETURNS text AS '$RUNTIME_BUNDLE', 'kwabi_hook_test_bind' LANGUAGE C STRICT;
CREATE TYPE posit16_1;
CREATE FUNCTION posit16_1_in(cstring) RETURNS posit16_1 AS '$RUNTIME_BUNDLE', 'kwabi_type_in' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_out(posit16_1) RETURNS cstring AS '$RUNTIME_BUNDLE', 'kwabi_type_out' LANGUAGE C IMMUTABLE STRICT;
CREATE TYPE posit16_1 (INPUT = posit16_1_in, OUTPUT = posit16_1_out, INTERNALLENGTH = 8,
                       PASSEDBYVALUE, ALIGNMENT = double);
$ops_sql
CREATE OPERATOR = (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_eq, COMMUTATOR = =, NEGATOR = <>);
CREATE OPERATOR <> (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_ne, COMMUTATOR = <>, NEGATOR = =);
CREATE OPERATOR < (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_lt, COMMUTATOR = >, NEGATOR = >=);
CREATE OPERATOR <= (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_le, COMMUTATOR = >=, NEGATOR = >);
CREATE OPERATOR > (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_gt, COMMUTATOR = <, NEGATOR = <=);
CREATE OPERATOR >= (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_ge, COMMUTATOR = <=, NEGATOR = <);
CREATE OPERATOR + (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_add, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_sub);
CREATE OPERATOR * (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_mul, COMMUTATOR = *);
CREATE OPERATOR / (LEFTARG = posit16_1, RIGHTARG = posit16_1, FUNCTION = posit16_1_div);
CREATE OPERATOR CLASS posit16_1_ops DEFAULT FOR TYPE posit16_1 USING btree AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 posit16_1_cmp(posit16_1, posit16_1);
SQL

check "bind the body" "bound" "$(Q "SELECT kwabi_hook_test_bind('posit16_1', '$body')")"

check "1 prints as 1" "1" "$(Q "SELECT '1'::posit16_1::text")"
check "0.5 prints as 0.5" "0.5" "$(Q "SELECT '0.5'::posit16_1::text")"
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

if [ "$fail" -eq 0 ]; then echo "posit16_1 passed (PG $major)"; else echo "FAILURES (PG $major)"; exit 1; fi
