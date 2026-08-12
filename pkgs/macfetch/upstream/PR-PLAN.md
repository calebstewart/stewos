# Plan: take the CPU/GPU core-count patch upstream

Instructions for whoever (or whatever) opens the pull request later. Assume no memory of the
session that produced the patch — everything needed is here or in the files referenced.

## What exists already

| Artifact | Path |
|---|---|
| The change itself | `pkgs/macfetch/cpu-gpu-core-counts.patch` |
| Issue text to file first | `pkgs/macfetch/upstream/issue-cpu-gpu-core-counts.md` |
| Unrelated bug reports | `pkgs/macfetch/upstream/issue-cache-*.md` |

The patch is generated against tag **`v2.3.1`** of `github.com/gantoreno/macfetch` and is the
canonical copy of the change. It is applied to the local Nix build via `patches` in
`pkgs/macfetch/default.nix`, so it stays exercised — if upstream merges it, drop the `patches`
line and bump the package version instead of maintaining two copies.

**Do not hand-rewrite the change.** Apply the patch and build on it.

## Scope

In scope: the CPU and GPU segment detail, and the `cpu`/`gpu` → `cpu.v2`/`gpu.v2` cache-key
bump the format change requires.

Out of scope: both cache bugs. They are real and the issue text is written, but the user
intends to review and file those separately. Do not fold fixes for them into this PR, and do
not file those issues without asking.

## Steps

1. **File the feature issue first.** Paste `issue-cpu-gpu-core-counts.md` (the `#` heading is
   the title, everything below is the body). Note its number.
2. Fork `gantoreno/macfetch`, clone, branch from `main`. Branch naming follows the merged-PR
   history: `feat/cpu-gpu-core-counts`.
3. Apply the patch. It is a `git diff` against `v2.3.1`, so `git apply` works directly; if
   `main` has drifted, `git apply -3` and resolve.
   ```sh
   git apply /path/to/stewos/pkgs/macfetch/cpu-gpu-core-counts.patch
   ```
4. **Reproduce CI locally before pushing.** `.github/workflows/ci.yml` runs four jobs on
   `macos-latest`, and clippy warnings fail the build:
   ```sh
   cargo check
   cargo test
   cargo clippy -- -D warnings
   cargo fmt --all -- --check
   ```
   With Nix and no rustup toolchain to hand:
   `nix shell nixpkgs#cargo nixpkgs#rustc nixpkgs#clippy nixpkgs#rustfmt`.
   `rustfmt.toml` sets `max_width = 100` — the formatting is picky about the long
   `CFStringCreateWithCString` call.
5. Sanity-check the output against the machine's own numbers:
   ```sh
   sysctl hw.logicalcpu hw.nperflevels hw.perflevel0.name hw.perflevel0.physicalcpu
   ioreg -rc AGXAccelerator -d 1 | grep gpu-core-count
   cargo run --release
   ```
6. Commit with a conventional-commit subject, matching the repo's history:
   `feat: report CPU and GPU core counts`.
7. Open the PR against `main` and **fill in `.github/PULL_REQUEST_TEMPLATE.md`** — tick "New
   feature", tick all four checklist boxes (they map exactly to the CI jobs above), and put
   `Closes #<issue>` under "Related Issues".

## Things the PR body must say

- The performance-level *names* are read from `hw.perflevelN.name`, not assumed. The machine
  this was developed on reports `Super` and `Performance`, not `Performance`/`Efficiency`, so
  a hardcoded `P`/`E` rendering would print labels macOS never used.
- No new dependencies. `Cargo.toml` and `Cargo.lock` are untouched; the IOKit and
  CoreFoundation symbols are declared in a hand-rolled `extern` block because `sysctl` and
  `libc` were already there and one integer did not justify pulling in `io-kit-sys`.
- The cache keys had to be versioned. `cache::fallback` never expires an entry, so without it
  existing users would keep seeing the old output and the change would look broken.
- **The Intel and pre-macOS-12 paths are untested** — no such hardware was available. They are
  structured to degrade to the current output (`hw.nperflevels < 2` drops the breakdown, an
  absent `AGXAccelerator` drops the core count) rather than to fail, but say so plainly and
  invite the maintainer to check.

## Gotchas

- If a maintainer asks for the core count as a *separate* segment rather than appended to the
  existing ones, note that new segments must be registered in **both** `segment_registry()`
  and `default_segments()` in `src/macfetch/utils/config.rs`, and that file's tests assert the
  count is `19` in two places (`test_default_segments_count`,
  `test_segment_registry_has_all_segments`). Both numbers need updating.
- `cargo test` will likely fail two `utils::cache::tests` on any machine where
  `/Library/Caches/macfetch` is owned by another uid. That is the pre-existing bug documented
  in `issue-cache-tests-pollute-real-cache.md`, not something this patch caused — confirm by
  stashing the patch and re-running before blaming it.
- `cache::fallback` takes a bare `fn() -> String`, not a closure type, so the segment closures
  must stay non-capturing.
