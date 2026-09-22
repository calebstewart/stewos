# The Nix flake builds the plugin with gcc16Stdenv, so it cannot be loaded by any Qt app in nixpkgs

**Repo this issue is for:** `hyprwm/hyprqt6engine`

## Summary

`nix/overlays.nix` pins `stdenv = prev.gcc16Stdenv` for the platform theme plugin. That
is the right choice for a Hyprland *application* — a standalone process resolves
`libstdc++.so.6` through its own RPATH — but a `platformthemes` plugin is `dlopen`'d into
a host process that already has a `libstdc++.so.6` mapped, and the dynamic loader matches
on SONAME, not RPATH. The plugin therefore gets the *host's* libstdc++.

nixpkgs builds its entire Qt stack with the default stdenv (gcc 15.3.0) while the Hypr
packages are overridden to gcc 16.2.0. So the plugin asks the host's gcc 15 libstdc++ for
a symbol version that only gcc 16 provides, and never loads:

```
qt.core.library: ".../hyprqt6engine-.../lib/qt-6/platformthemes/libhyprqt6engine.so"
cannot load: Cannot load library .../libhyprqt6engine.so:
/nix/store/...-gcc-15.3.0-lib/lib/libstdc++.so.6: version `GLIBCXX_3.4.36' not found
(required by .../libhyprqt6engine.so)
```

The result is that `QT_QPA_PLATFORMTHEME=hyprqt6engine` is a no-op on NixOS today.

## Why this is easy to miss

Nothing reports it. Qt logs the load failure only under `QT_DEBUG_PLUGINS=1`, then falls
back to having *no* platform theme at all. The user-visible consequence is indirect:
with no platform theme there is no `QPlatformTheme::SystemIconThemeName` hint, so
`QIcon::themeName()` is empty and **every** `QIcon::fromTheme` lookup in the process
returns a null icon.

In practice that shows up as broken-image placeholders wherever an app draws an icon by
freedesktop name — status tray items, notification icons, menu icons — while icons
supplied as pixmaps or absolute paths keep working. It reads as a broken icon theme
rather than a plugin that failed to load.

## Environment

- hyprqt6engine rev `d0ce29c` (2026-08-11)
- nixpkgs `nixos-unstable`: default stdenv gcc 15.3.0, `qt6Packages.qtbase` 6.11.1
- Host app: quickshell 0.3.0 (gcc 15.3.0); reproduces with any nixpkgs Qt 6 app
- Hyprland 0.56.2, NixOS

## Reproduction

```console
$ QT_DEBUG_PLUGINS=1 QT_QPA_PLATFORMTHEME=hyprqt6engine <any nixpkgs qt6 app> 2>&1 \
    | grep hyprqt6engine
...
qt.core.plugin.loader: QLibraryPrivate::loadPlugin failed on
  ".../libhyprqt6engine.so" : "... version `GLIBCXX_3.4.36' not found ..."
```

Observed against quickshell, resolving an icon by name:

| `QT_QPA_PLATFORMTHEME` | `QIcon::fromTheme("view-refresh")` |
| --- | --- |
| `hyprqt6engine` | null |
| unset | null |
| `gtk3` (in-tree qtbase plugin) | resolves |

## Scope

It is not only the plugin's own objects. `libhyprlang.so` and `libhyprutils.so` also
export/require `GLIBCXX_3.4.36`, and nixpkgs builds both with `gcc16Stdenv`, so any fix
has to move those to the Qt stdenv as well.

## Suggested fix

Build the plugin — and the Hypr libraries it links — with the same stdenv as the qtbase it
plugs into, rather than with the ecosystem-wide gcc16Stdenv:

```nix
hyprqt6engine = final: prev: {
  hyprqt6engine =
    let
      qtStdenv = prev.qt6Packages.qtbase.stdenv;
    in
    prev.callPackage ./default.nix {
      stdenv = qtStdenv;
      hyprutils = prev.hyprutils.override { stdenv = qtStdenv; };
      hyprlang = prev.hyprlang.override { stdenv = qtStdenv; };
      version = ...;
    };
};
```

All three compile cleanly under gcc 15.3.0 — this was verified by building them that way
and confirming the plugin then loads and resolves themed icons in quickshell. Deriving the
stdenv from `qt6Packages.qtbase` rather than naming a gcc version keeps it correct as
nixpkgs moves its Qt stack forward, and keeps working for downstreams whose Qt is already
on gcc 16.
