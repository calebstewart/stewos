# `cargo test` writes to the real `/Library/Caches/macfetch` and leaves state on the host

> Ready-to-paste issue body for `gantoreno/macfetch`. Not filed yet.
> Type: bug. Observed on macfetch 2.3.1, macOS 26.5.2.
> Shares a root cause with the "cache directory is system-wide" issue; the two could
> reasonably be filed as one.

## Problem

The three tests in `src/macfetch/utils/cache.rs` operate on the real, hardcoded
`CACHE_DIR` (`/Library/Caches/macfetch`) rather than a temporary directory:

- `test_fallback_computes_value_when_no_cache` removes `…/test_no_cache`
- `test_fallback_returns_cached_value` runs `create_dir_all(CACHE_DIR)` and writes
  `…/test_cached`
- `test_fallback_creates_cache_file` writes and removes `…/test_creates_cache`

So `cargo test` mutates system state outside the build tree. Three consequences:

**1. It creates a machine-wide directory as whatever uid runs the tests.** Packaging
macfetch with Nix runs `cargo test` in `checkPhase`, and that left this behind on my
machine:

```console
$ /bin/ls -ld /Library/Caches/macfetch
drwxr-xr-x  2 _nixbld1  admin  64 Aug 12 14:03 /Library/Caches/macfetch
```

`_nixbld1` is the sandboxed build user. Nothing in the build asked for a directory outside
the sandbox; the tests reached out and made one. That directory then made macfetch's cache
permanently unwritable for my login user (the companion issue).

**2. The test suite now fails on that machine**, and the failure has nothing to do with the
code under test:

```
test macfetch::utils::cache::tests::test_fallback_creates_cache_file ... FAILED
test macfetch::utils::cache::tests::test_fallback_returns_cached_value ... FAILED

thread '…test_fallback_creates_cache_file' panicked at src/macfetch/utils/cache.rs:85:9:
assertion failed: Path::new(&cache_path).exists()
```

Both are just `EACCES` on a directory owned by another uid, surfaced as an assertion
failure. Reproducible on a pristine `v2.3.1` checkout.

**3. The tests race a real macfetch run** and any other concurrent `cargo test`, since they
all share one fixed path with fixed file names.

## Suggested fix

Make the cache directory resolvable rather than a `const`, so tests can point it somewhere
disposable — e.g. a `MACFETCH_CACHE_DIR` environment override, or a `fallback_in(dir, …)`
taking the directory as a parameter with `fallback()` as the thin wrapper that supplies the
default. Either lets the tests use `std::env::temp_dir()` and clean up after themselves.

That change pairs naturally with moving the default to `~/Library/Caches/macfetch` (the
companion issue) — one refactor of `CACHE_DIR` addresses both.

## Workaround for packagers

Skip the module until this is fixed. For a Nix `buildRustPackage`:

```nix
checkFlags = [ "--skip=macfetch::utils::cache::tests" ];
```
