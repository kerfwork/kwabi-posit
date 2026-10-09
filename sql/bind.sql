-- Binds this library as the body of posit16_1. Run after install.sql.
--
-- kwabi_hook_test_bind is a test function in the runtime bundle. A production binder is
-- the runtime's loader; this is the stand-in until that exists.
--
-- Run with: psql -v runtime='...' -v body='/abs/path/libkwabi_posit16_1.<dl>' -f sql/bind.sql

CREATE FUNCTION kwabi_hook_test_bind(text, text) RETURNS text
    AS :'runtime', 'kwabi_hook_test_bind' LANGUAGE C STRICT;
SELECT kwabi_hook_test_bind('posit16_1', :'body') AS bound;
