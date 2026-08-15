# flakedoc's extraction half.
#
# Everything a documentation site needs to know about a flake is already inside
# it -- the module system records where each option was declared and defined,
# meta describes every package, and the lock file describes every input. This
# namespace reads all of that out and writes it to one JSON document; the
# flakedoc binary turns that document into a site.
#
# The split is deliberate. Evaluating a flake is slow, needs the flake's own
# inputs, and can only be done by Nix; rendering HTML is none of those things.
# Keeping a serialized document between them means the renderer can be worked on
# without re-evaluating anything, and a flake that cannot be evaluated on one
# machine can be evaluated on several and merged.
#
# In keeping with the rest of lib/, this file takes a nixpkgs lib and returns
# plain functions. Those functions take pkgs as an argument rather than
# capturing one, so nothing here depends on a package set or on a flake input.
{ lib }:
let
  optionsLib = import ./options.nix { inherit lib; };
  hostsLib = import ./hosts.nix { inherit lib; };
  packagesLib = import ./packages.nix { inherit lib; };
  outputsLib = import ./outputs.nix { inherit lib; };
  nixdocLib = import ./nixdoc.nix { inherit lib; };

  # The document format. Bump this when the renderer would misread an older
  # document, not when a field is added -- flakedoc ignores fields it does not
  # know.
  schemaVersion = 1;

  # Tested by what it is not, rather than with lib.isPath: a config is routinely
  # a string path ("${self}/docs/flakedoc.toml") as well as a path literal, and
  # an isPath test quietly treats the string as the configuration itself and
  # generates an empty site.
  readConfig =
    config: if lib.isAttrs config then config else builtins.fromTOML (builtins.readFile config);

in
# rec rather than a let-bound attrset: nixdoc reads doc-comments off the
# bindings of a file's top-level attrset, and would find none through a
# wrapper.
rec {
  inherit (optionsLib) evalTree mkOptionSet;
  inherit (hostsLib) mkHost optionPathsOf;
  inherit (packagesLib) mkPackage;
  inherit (outputsLib) mkOutputs mkInputs;
  inherit (nixdocLib) mkLibDocs;

  /**
    Extract a flake into a single JSON document.

    # Inputs

    `pkgs`
    : Package set the document is *built* with. Its system is the system the
      documentation is generated on, which need not be a system the flake
      targets -- a darwin option set evaluates and renders perfectly well from
      Linux, since reading an option tree never builds anything.

    `self`
    : The flake being documented.

    `inputs`
    : That flake's inputs. Module trees are evaluated with these as specialArgs.

    `config`
    : A path to a `flakedoc.toml`, or the same structure as an attrset.

    `pkgsBySystem`
    : Package sets to evaluate option sets against, keyed by system. Defaults to
      `pkgs` under its own system, which is enough for a single-platform flake.

    `stubs`
    : Extra modules per option-set id, for anything a tree needs before its
      options can be read. Keep these minimal: whatever they set shows up in the
      rendered default of every option that reads `config`.

    # Example

    ```nix
    lib.docs.mkDocsJSON {
      pkgs = pkgsFor.x86_64-linux;
      inherit self inputs;
      config = ./docs/flakedoc.toml;
      pkgsBySystem = pkgsFor;
    }
    ```

    # Type

    ```
    mkDocsJSON :: AttrSet -> Derivation
    ```
  */
  mkDocsJSON =
    {
      pkgs,
      self,
      inputs,
      config,
      pkgsBySystem ? {
        ${pkgs.stdenv.hostPlatform.system} = pkgs;
      },
      stubs ? { },
    }:
    let
      cfg = readConfig config;
      site = cfg.site or { };

      src = self.outPath;
      repoUrl = lib.removeSuffix "/" (site.repository or "");
      branch = site.branch or "main";

      pkgsForSystem =
        system:
        pkgsBySystem.${system}
          or (throw "flakedoc: no package set for system '${system}'; pass one in pkgsBySystem");

      # --- options -------------------------------------------------------

      optionSets = map (
        set:
        optionsLib.mkOptionSet {
          docPkgs = pkgs;
          inherit
            src
            repoUrl
            branch
            set
            ;
          exclude = set.exclude or (site.excludeOptions or [ ]);
          warningsAreErrors = set.warningsAreErrors or (site.warningsAreErrors or false);
          options = optionsLib.evalTree {
            inherit (set) kind;
            inherit src inputs;
            pkgs = pkgsForSystem set.system;
            modules = set.modules;
            stub = stubs.${set.id} or [ ];
          };
        }
      ) (cfg.optionSets or [ ]);

      # --- hosts ---------------------------------------------------------

      # A host is walked using the option paths of the sets that share its kind:
      # a home configuration has no NixOS options to look up, and looking them
      # up anyway would only cost time.
      pathsFor = kind: hostsLib.optionPathsOf (lib.filter (s: s.kind == kind) optionSets);

      configurationsOf =
        kind: attr:
        lib.mapAttrsToList (name: c: {
          inherit name kind;
          configuration = c;
        }) (self.${attr} or { });

      hosts =
        map
          (
            h:
            hostsLib.mkHost {
              inherit (h) name kind configuration;
              inherit src repoUrl branch;
              optionPaths = pathsFor h.kind;
              facts = site.hostFacts or [ ];
            }
          )
          (
            configurationsOf "nixos" "nixosConfigurations"
            ++ configurationsOf "darwin" "darwinConfigurations"
            ++ configurationsOf "home-manager" "homeConfigurations"
          );

      # --- packages ------------------------------------------------------

      packages = lib.concatLists (
        lib.mapAttrsToList (
          system: entries:
          lib.mapAttrsToList (
            attr: drv:
            packagesLib.mkPackage {
              inherit
                attr
                drv
                system
                src
                repoUrl
                branch
                ;
              packageDir = site.packageDir or "pkgs";
            }
          ) entries
        ) (self.packages or { })
      );

      # --- assembly ------------------------------------------------------

      base = {
        inherit schemaVersion;

        meta = {
          name = site.name or (site.title or "flake");
          title = site.title or (site.name or "flake");
          description = site.description or null;
          inherit repoUrl branch;
          rev = self.rev or self.dirtyRev or null;
          lastModified = self.lastModifiedDate or null;
        };

        inherit optionSets hosts packages;

        outputs = outputsLib.mkOutputs { inherit self; };
        inputs = outputsLib.mkInputs { lockFile = "${src}/flake.lock"; };
      };

      baseFile = pkgs.writeText "flakedoc-base.json" (builtins.toJSON base);

      namespaces = cfg.libNamespaces or [ ];
      libFile =
        if namespaces == [ ] then
          pkgs.writeText "flakedoc-lib.json" "[]"
        else
          nixdocLib.mkLibDocs {
            inherit
              pkgs
              src
              repoUrl
              branch
              namespaces
              ;
          };
    in
    pkgs.runCommand "flakedoc-docs.json" { } ''
      ${lib.getExe pkgs.jq} \
        --slurpfile libNamespaces ${libFile} \
        '. + { libNamespaces: $libNamespaces[0] }' \
        ${baseFile} > $out
    '';

  /**
    Build a flake's documentation site.

    Takes everything [`mkDocsJSON`](#function-library-lib.docs.mkDocsJSON) does,
    plus the prose to weave in, and runs the renderer over the result.

    # Inputs

    `content`
    : Directory of hand-written Markdown, or `null` for reference pages only.

    `flakedoc`
    : The renderer. Defaults to the one in the StewOS package scope.

    `templates`
    : Directory of minijinja templates overriding the built-in ones, or `null`.

    # Example

    ```nix
    packages.x86_64-linux.docs = self.lib.docs.mkSite {
      pkgs = pkgsFor.x86_64-linux;
      inherit self inputs;
      config = ./docs/flakedoc.toml;
      content = ./docs/content;
    };
    ```

    # Type

    ```
    mkSite :: AttrSet -> Derivation
    ```
  */
  mkSite =
    {
      pkgs,
      self,
      inputs,
      config,
      content ? null,
      templates ? null,
      flakedoc ? pkgs.stewos.flakedoc,
      pkgsBySystem ? {
        ${pkgs.stdenv.hostPlatform.system} = pkgs;
      },
      stubs ? { },
    }:
    let
      json = mkDocsJSON {
        inherit
          pkgs
          self
          inputs
          config
          pkgsBySystem
          stubs
          ;
      };
      configFile =
        if lib.isPath config then config else pkgs.writeText "flakedoc.json" (builtins.toJSON config);
    in
    pkgs.runCommand "flakedoc-site"
      {
        nativeBuildInputs = [ flakedoc ];
        meta.description = "Generated documentation for ${self.outPath}";
      }
      ''
        flakedoc build \
          --input ${json} \
          --config ${configFile} \
          ${lib.optionalString (content != null) "--content ${content}"} \
          ${lib.optionalString (templates != null) "--template-dir ${templates}"} \
          --out $out
      '';
}
