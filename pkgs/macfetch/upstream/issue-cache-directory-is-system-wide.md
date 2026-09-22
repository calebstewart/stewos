# Cache directory is system-wide, so caching silently stops working for every user but the first

> Ready-to-paste issue body for `gantoreno/macfetch`. Not filed yet.
> Type: bug. Observed on macfetch 2.3.1, macOS 26.5.2.
> Shares a root cause with the "unit tests write to the real cache directory" issue; the two
> could reasonably be filed as one.

## Problem

`src/macfetch/utils/cache.rs` hardcodes a machine-wide cache path:

```rust
const CACHE_DIR: &str = "/Library/Caches/macfetch";
```

`/Library/Caches` is the *system* cache domain. Per-user caches belong in
`~/Library/Caches`. Because macfetch is a per-user CLI writing per-user data there, the
first uid to run it creates `/Library/Caches/macfetch` owned by that uid with mode `0755`,
and every other user on the machine then fails to write into it forever.

Nothing surfaces when that happens. Both fallible calls in `fallback()` discard their
errors:

```rust
fs::create_dir_all(CACHE_DIR).ok();
fs::write(&cache_path, &value).ok();
```

So the failure mode is not an error, it is macfetch quietly recomputing the CPU and GPU
values on every single run — exactly the work the cache exists to avoid — with no way for
the user to notice, and no way to fix it without `sudo`.

## Reproduction

Any second user account reproduces it. On my machine the directory ended up owned by a
package-manager build user:

```console
$ /bin/ls -ld /Library/Caches/macfetch
drwxr-xr-x  2 _nixbld1  admin  64 Aug 12 14:03 /Library/Caches/macfetch

$ /bin/ls -A /Library/Caches/macfetch
$ macfetch >/dev/null && /bin/ls -A /Library/Caches/macfetch
$
```

The directory stays empty: every write is attempted, fails with `EACCES`, and is thrown
away by `.ok()`. Caching has been off on this machine ever since, silently.

(How a build user came to own it is the subject of the companion issue — the unit tests
write to this same real path, so any sandboxed build of macfetch that runs `cargo test`
creates it.)

## Suggested fix

Resolve the cache directory under the user's own cache domain, falling back gracefully when
`HOME` is unset:

```rust
fn cache_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(|home| PathBuf::from(home).join("Library/Caches/macfetch"))
}
```

`utils/config.rs` already reads `HOME` this way for the config file, so the pattern is
established in the codebase.

Worth considering alongside it: `fallback()` currently cannot report that caching is
broken. Even a one-line `eprintln!` behind a debug flag would have made this diagnosable.
