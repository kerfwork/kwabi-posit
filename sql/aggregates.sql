-- Standard aggregates for posit16_1: sum, avg, max, min.
--
-- Run after install.sql and bind.sql. None of them needs new runtime support: sum steps
-- with the type's own addition, and the others are plain SQL functions over the type's
-- comparison operators. The aggregate-state limits are discussed in README.md.

-- sum: the state is the running total. There is no initial condition, so the first value
-- becomes the state (posit16_1_add is strict), and an empty input is NULL, as in SQL.
CREATE AGGREGATE sum(posit16_1) (SFUNC = posit16_1_add, STYPE = posit16_1);

-- max and min: a null state means "no value yet".
CREATE FUNCTION posit16_1_max_step(posit16_1, posit16_1) RETURNS posit16_1
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN $1 IS NULL THEN $2
                WHEN $2 IS NULL THEN $1
                WHEN $1 >= $2 THEN $1
                ELSE $2 END
$$;
CREATE FUNCTION posit16_1_min_step(posit16_1, posit16_1) RETURNS posit16_1
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN $1 IS NULL THEN $2
                WHEN $2 IS NULL THEN $1
                WHEN $1 <= $2 THEN $1
                ELSE $2 END
$$;
CREATE AGGREGATE max(posit16_1) (SFUNC = posit16_1_max_step, STYPE = posit16_1);
CREATE AGGREGATE min(posit16_1) (SFUNC = posit16_1_min_step, STYPE = posit16_1);

-- avg: the state collects the values; the final function sums them and divides by the
-- count. Collecting is simple and exact in the array; the division is one posit rounding.
CREATE FUNCTION posit16_1_collect(posit16_1[], posit16_1) RETURNS posit16_1[]
    LANGUAGE sql IMMUTABLE AS $$ SELECT $1 || $2 $$;
CREATE FUNCTION posit16_1_avg_final(posit16_1[]) RETURNS posit16_1
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN cardinality($1) = 0 THEN NULL
                ELSE (SELECT sum(x) FROM unnest($1) AS x) / (cardinality($1)::text)::posit16_1
           END
$$;
CREATE AGGREGATE avg(posit16_1) (SFUNC = posit16_1_collect, STYPE = posit16_1[],
                                 FINALFUNC = posit16_1_avg_final, INITCOND = '{}');
