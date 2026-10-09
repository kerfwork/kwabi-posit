-- posit16_1: the type, its operators and its btree operator class.
--
-- Run with: psql -v runtime='/abs/path/kwabi_runtime_pgNN.<dl>' -f sql/install.sql
--
-- The runtime bundle supplies the generic functions (kwabi_type_in, kwabi_type_out,
-- kwabi_type_binop). The body is bound separately (see sql/bind.sql).

CREATE TYPE posit16_1;
CREATE FUNCTION posit16_1_in(cstring) RETURNS posit16_1
    AS :'runtime', 'kwabi_type_in' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_out(posit16_1) RETURNS cstring
    AS :'runtime', 'kwabi_type_out' LANGUAGE C IMMUTABLE STRICT;
CREATE TYPE posit16_1 (INPUT = posit16_1_in, OUTPUT = posit16_1_out,
                       INTERNALLENGTH = 8, PASSEDBYVALUE, ALIGNMENT = double);

-- One SQL function per operator; all of them call the runtime's kwabi_type_binop.
CREATE FUNCTION posit16_1_eq(posit16_1, posit16_1) RETURNS boolean AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_ne(posit16_1, posit16_1) RETURNS boolean AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_lt(posit16_1, posit16_1) RETURNS boolean AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_le(posit16_1, posit16_1) RETURNS boolean AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_gt(posit16_1, posit16_1) RETURNS boolean AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_ge(posit16_1, posit16_1) RETURNS boolean AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_add(posit16_1, posit16_1) RETURNS posit16_1 AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_sub(posit16_1, posit16_1) RETURNS posit16_1 AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_mul(posit16_1, posit16_1) RETURNS posit16_1 AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_div(posit16_1, posit16_1) RETURNS posit16_1 AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION posit16_1_cmp(posit16_1, posit16_1) RETURNS int4 AS :'runtime', 'kwabi_type_binop' LANGUAGE C IMMUTABLE STRICT;

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
