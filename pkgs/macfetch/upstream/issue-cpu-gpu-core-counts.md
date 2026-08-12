# CPU and GPU segments print only the marketing name, which does not identify the hardware

> Ready-to-paste issue body for `gantoreno/macfetch`. Not filed yet.
> Type: feature request. Observed on macfetch 2.3.1, macOS 26.5.2, Apple M5 Pro.

## Problem

On Apple Silicon the `cpu` and `gpu` segments print the same marketing string twice:

```
CPU: Apple M5 Pro
GPU: Apple M5 Pro
```

A chip name is not a machine. "M5 Pro" covers several bins with different CPU and GPU core
counts, so neither line distinguishes one Mac from another, and the GPU line adds no
information the CPU line did not already give.

This happens because both segments take the shortest available route
(`src/macfetch/segments/mod.rs`):

- `cpu()` returns `machdep.cpu.brand_string` verbatim.
- `gpu()` returns the Metal device name from `CGDirectDisplayCopyCurrentMetalDevice`, which
  on Apple Silicon is that same marketing string.

Neofetch prints the core count in parentheses on its CPU line, so this is also a gap against
the aesthetic macfetch is targeting.

## The detail macOS already exposes

All of this is available cheaply, and all of it was verified on the machine above:

| Source | Key | Value |
|---|---|---|
| sysctl | `hw.logicalcpu` | `15` |
| sysctl | `hw.nperflevels` | `2` |
| sysctl | `hw.perflevel0.name` / `hw.perflevel0.physicalcpu` | `Super` / `5` |
| sysctl | `hw.perflevel1.name` / `hw.perflevel1.physicalcpu` | `Performance` / `10` |
| IORegistry | `AGXAccelerator` → `gpu-core-count` | `16` |

### Read the performance-level names, do not assume them

This is the part worth flagging. Nearly every "count the P and E cores" implementation
hardcodes the pair `Performance`/`Efficiency`. **This machine reports `Super` and
`Performance`** — there is no level named `Efficiency`:

```console
$ sysctl hw.nperflevels hw.perflevel0.name hw.perflevel1.name
hw.nperflevels: 2
hw.perflevel0.name: Super
hw.perflevel1.name: Performance
```

Anything that renders `10P + 5E` would be printing a label macOS never used. Reading
`hw.perflevelN.name` is both correct today and immune to Apple adding another tier later.

## Suggested output

```
CPU: Apple M5 Pro (15) [5 Super + 10 Performance]
GPU: Apple M5 Pro (16 cores)
```

Degrading on hardware without the extra detail (an Intel Mac, or macOS older than 12, where
the `hw.perflevel*` keys do not exist):

```
CPU: Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz (12)
GPU: Intel UHD Graphics 630
```

Notes on the specifics:

- The parenthesised total is `hw.logicalcpu` (threads), matching what Neofetch prints.
- The bracketed breakdown uses each level's `physicalcpu`, and is omitted when
  `hw.nperflevels < 2`. Threads and cores can only disagree under hyperthreading, which is
  Intel-only, and Intel reports a single performance level — so the two numbers never
  visibly fail to add up.
- `gpu-core-count` is not reachable through Metal; `MTLDevice` has no such property. It has
  to come from the IORegistry, and only exists on Apple Silicon. Everything else keeps the
  bare device name.

## Implementation notes

A working implementation needs no new crates. `sysctl` and `libc` are already dependencies,
and the four IOKit plus five CoreFoundation symbols needed for `gpu-core-count` can be
declared in a hand-rolled `extern` block, keeping `Cargo.toml` and `Cargo.lock` untouched.
A few things to get right there:

- The dictionary from `IOServiceMatching` is *consumed* by `IOServiceGetMatchingService`;
  releasing it as well is a double free.
- Pass `0` (`MACH_PORT_NULL`) as the main port rather than naming `kIOMasterPortDefault`,
  which was renamed `kIOMainPortDefault` in macOS 12.
- Check `CFGetTypeID(prop) == CFNumberGetTypeID()` before `CFNumberGetValue` — that call is
  undefined on any other CF type.
- A matching service of `0` means the class is absent. That is the ordinary Intel path, not
  an error.

### One coupled detail: the cache

`cache::fallback` never expires an entry, and `cpu`/`gpu` are both cached. Any change to
these formats must also change the cache keys (e.g. `cpu` → `cpu.v2`), or every existing
user keeps seeing the old single-word output indefinitely and the feature looks broken.

I have a patch implementing all of the above against `v2.3.1` — it passes `cargo check`,
`cargo test`, `cargo clippy -- -D warnings` and `cargo fmt --all -- --check`, and produces
exactly the output shown above. Happy to open a PR if the approach and formatting look
right to you.

The Intel and pre-macOS-12 fallback paths are untested for lack of hardware; they are
structured to degrade to the current output rather than fail.
