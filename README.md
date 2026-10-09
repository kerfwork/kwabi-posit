# kwabi-posit

`posit<16,1>` as a PostgreSQL type, built on the [Universal](https://github.com/stillwater-sc/universal)
library (MIT, header-only C++) through the [kwabi](https://github.com/kerfwork/kwabi-runtime) ABI.

It is a worked example for extension authors: the type's text I/O, operators and btree
ordering, each implemented as a kwabi type body. The runtime supplies the SQL functions;
this library supplies the bodies. Reloading a body needs no restart.

## What it does

- Input and output: plain decimal. Output is the shortest decimal that reads back to the
  same value. NaR prints as `NaR`.
- Overflow saturates to `maxpos`/`maxneg`, as posits do. It is not an error.
- Operators: `= <> < <= > >=`, `+ - * /`, and a `DEFAULT` btree operator class, so `ORDER BY`
  and an index work.
- Errors: a bad literal is `22P02`; division by zero is `22012`; an operation that yields NaR
  is `22003`.
- `%` is not defined for posits and is refused with `0A000`.
- NaR is equal only to NaR and greater than every other value, so the btree order is total.

## Layout

- `third_party/universal`: Universal, a git submodule pinned to `8f9968fe`.
- `include/kwabi.h`: the runtime's ABI header, copied at a fixed commit (see `include/PROVENANCE.md`).
- `src/posit16_1.cpp`: the body. It exports `kwabi_type_bodies()`.
- `tests/body_test.cpp`: the body through its table, with no PostgreSQL. It round-trips all
  65,535 encodings except NaR through text.
- `posit-run.sh`: the PostgreSQL check, run against a preloaded runtime bundle.

## Build and run

    git submodule update --init
    make test                                   # the body, no PostgreSQL
    RUNTIME_BUNDLE=<kwabi_runtime_pgNN.dylib> SCRATCH=<dir> ./posit-run.sh 18   # and 16, 17

`RUNTIME_BUNDLE` is built from kwabi-runtime (`make build PG=<major>`). The script starts a
preloaded cluster, creates the type through the runtime's functions, binds the body, and
runs the checks.

The body needs no PostgreSQL headers, so one library serves 16, 17 and 18.

## Licenses

This repository is AGPL-3.0-or-later (see `LICENSE`). Universal is MIT-licensed; its licence
is in the submodule.
