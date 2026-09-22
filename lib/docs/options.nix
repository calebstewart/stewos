# Option extraction.
#
# Everything here funnels into nixpkgs' own nixosOptionsDoc, which already knows
# how to walk submodules, render defaults that cannot be serialized, and turn an
# option tree into a flat attrset keyed by dotted name. What this file adds is
# the two things it does not do: evaluating a module tree without a real machine
# to point it at, and deciding which of the resulting options belong to the flake
# being documented rather than to nixpkgs, home-manager or stylix.
{ lib }:
let
  # A module tree cannot be evaluated on its own. modules/nixos/default.nix (and
  # its home-manager and darwin counterparts) import third-party module sets
  # which probe for options only a real evaluation declares -- stylix's nvf
  # module reads options.programs, for instance -- so lib.evalModules over the
  # tree fails the moment .options is touched. Each tree therefore goes through
  # its real evaluator, against a host that does not exist.
  #
  # The stub is deliberately minimal. Anything it sets leaks into the rendered
  # defaults of options that read config, which is the whole reason this is not
  # simply evaluated against one of the flake's actual hosts.
  evaluators = {
    nixos =
      {
        pkgs,
        inputs,
        modules,
        stub,
      }:
      lib.nixosSystem {
        inherit pkgs;
        specialArgs = { inherit inputs; };
        modules =
          modules
          ++ [
            {
              networking.hostName = "example";
              system.stateVersion = lib.trivial.release;
            }
          ]
          ++ stub;
      };

    home-manager =
      {
        pkgs,
        inputs,
        modules,
        stub,
      }:
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules =
          modules
          ++ [
            {
              home.username = "example";
              home.homeDirectory =
                if pkgs.stdenv.hostPlatform.isDarwin then "/Users/example" else "/home/example";
            }
          ]
          ++ stub;
      };

    darwin =
      {
        pkgs,
        inputs,
        modules,
        stub,
      }:
      inputs.nix-darwin.lib.darwinSystem {
        inherit pkgs;
        specialArgs = { inherit inputs; };
        modules = modules ++ [ { networking.hostName = "example"; } ] ++ stub;
      };
  };
in
rec {
  inherit evaluators;

  /**
    Evaluate one module tree against a synthetic host and return its `options`.

    The tree is addressed through the flake's own store path rather than a
    relative one. That is load-bearing: an option's `declarations` record the
    store path the module was read from, and `isOurs` below recognises a flake's
    own options by that prefix. Importing `./modules/nixos` from an expression
    copies the directory to a *different* store path, and the filter then
    silently matches nothing.

    # Inputs

    `kind`
    : Which evaluator to use -- one of `nixos`, `home-manager` or `darwin`.

    `pkgs`
    : The package set to evaluate against. Must match the option set's system,
      which is not necessarily the system the documentation is built on.

    `inputs`
    : The documented flake's inputs, handed to the module system as specialArgs.

    `src`
    : The documented flake's source, normally `self.outPath`.

    `modules`
    : Source-relative paths of the module trees to evaluate, e.g.
      `[ "modules/nixos" ]`.

    `stub`
    : Extra modules defining whatever the tree needs before its options can be
      read. Keep this as small as it will go.

    # Type

    ```
    evalTree :: AttrSet -> AttrSet
    ```
  */
  evalTree =
    {
      kind,
      pkgs,
      inputs,
      src,
      modules,
      stub ? [ ],
    }:
    let
      evaluator =
        evaluators.${kind}
          or (throw "flakedoc: unknown option set kind '${kind}'; expected one of ${lib.concatStringsSep ", " (lib.attrNames evaluators)}");
    in
    (evaluator {
      inherit pkgs inputs stub;
      modules = map (m: "${src}/${m}") modules;
    }).options;

  /**
    Render an evaluated option tree into a documentation record.

    Options are kept when at least one of their declarations lives inside `src`.
    That is a better filter than matching an option-name prefix: it needs no
    configuration, it cannot be fooled by a third-party module that happens to
    share a namespace, and it catches options a flake declares *outside* its own
    namespace -- StewOS's darwin tree, for example, declares `programs.nh` and
    nothing under `stewos.*` at all.

    It has one blind spot. A module imported as a *value* rather than as a path
    -- `imports = [ inputs.foo.homeManagerModules.default ]` -- has no file of
    its own to be attributed to, so the module system credits its options to the
    file that imported it. Those options then look, correctly as far as anything
    here can tell, like the importing flake's own.

    The better remedy is at the import rather than here: giving the import a
    file restores the attribution, and improves that module's error messages
    while it is at it.

    ```nix
    imports = [
      {
        _file = "${inputs.foo}/nix/hm-module.nix";
        imports = [ inputs.foo.homeManagerModules.default ];
      }
    ];
    ```

    `exclude` is for when that is not available -- an import buried inside a
    module you do not control.

    # Inputs

    `docPkgs`
    : Package set used to *build* the JSON. This is the system the docs are
      built on, which need not be the system the options were evaluated for --
      that split is what lets a Linux machine render the darwin option set.

    `options`
    : The `options` attrset from [`evalTree`](#function-library-lib.docs.evalTree).

    `set`
    : The option set's `{ id, title, kind, system, ... }` record from the
      configuration file.

    `exclude`
    : Dotted option-name prefixes to drop even though they pass the declaration
      filter. See above for the one case that needs this.

    # Type

    ```
    mkOptionSet :: AttrSet -> AttrSet
    ```
  */
  mkOptionSet =
    {
      docPkgs,
      options,
      src,
      repoUrl,
      branch,
      set,
      exclude ? [ ],
      warningsAreErrors ? false,
    }:
    let
      prefix = "${toString src}/";
      isOurs = decl: lib.hasPrefix prefix (toString decl);
      rel = decl: lib.removePrefix prefix (toString decl);

      name = o: lib.showOption o.loc;
      isExcluded =
        o: lib.any (p: o.loc == lib.splitString "." p || lib.hasPrefix "${p}." (name o)) exclude;

      doc = docPkgs.nixosOptionsDoc {
        inherit options warningsAreErrors;

        transformOptions =
          o:
          if isExcluded o || !(lib.any isOurs o.declarations) then
            # Not ours. nixosOptionsDoc drops invisible options, so this is how
            # nixpkgs', home-manager's and stylix's thousands get discarded.
            o // { visible = false; }
          else
            o
            // {
              declarations = map (d: {
                name = rel d;
                url = "${repoUrl}/blob/${branch}/${rel d}";
              }) o.declarations;
            };
      };
    in
    {
      inherit (set)
        id
        title
        kind
        system
        ;
      description = set.description or null;
      options = doc.optionsNix;
    };
}
