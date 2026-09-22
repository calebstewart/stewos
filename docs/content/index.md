# StewOS

A Nix flake managing NixOS, nix-darwin and Home-Manager configurations for
several machines, along with the modules, packages and helper libraries they are
built from. Every option it declares lives under `stewos.*`.

This site is generated from the flake itself. The option reference is evaluated
out of the module trees, the package pages out of `meta`, the host pages out of
what each machine actually sets, and the library reference out of the
doc-comments in `lib/`. Nothing on it is maintained by hand, so nothing on it can
drift from the code.

## Where to start

- **[Options](options/index.html)** — every option, searchable, across NixOS,
  Home-Manager and nix-darwin. This is the page you want.
- **[Hosts](hosts/index.html)** — the four real configurations, shown as worked
  examples: which modules each turns on and every option it sets.
- **[Packages](packages/index.html)** — what the flake builds, reachable as
  `pkgs.stewos.<name>` once its overlay is applied.
- **[Library](lib/index.html)** — the pure helpers under `lib/`, including the
  documentation generator that produced this site.
- **[Flake](flake/index.html)** — outputs and inputs.

## Using it

```nix
{
  inputs.stewos.url = "github:calebstewart/stewos";

  outputs = { nixpkgs, stewos, ... }: {
    nixosConfigurations.mine = nixpkgs.lib.nixosSystem {
      # StewOS's modules reference StewOS's inputs from inside "imports", where
      # only specialArgs exist. Handing them back is not optional.
      specialArgs = { inputs = stewos.lib.moduleInputs; };

      modules = [
        stewos.nixosModules.default
        { nixpkgs.overlays = [ stewos.overlays.default ]; }
        ./configuration.nix
      ];
    };
  };
}
```

`templates/nixos-single` is a worked version of the same thing:

```console
$ nix flake init -t github:calebstewart/stewos#nixos-single
```

Because the modules reach for `inputs` by name, `inputs` inside a StewOS module
always means *StewOS's* inputs, never the consuming flake's. Pass your own under
a different name.
