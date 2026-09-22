# Host extraction -- the reference documentation's worked examples.
#
# A host directory holds almost nothing worth describing on its own. What is
# worth describing is the shape of a real configuration: which of the flake's
# modules it turns on, and every option it sets away from its default. The
# module system already records that, one definition at a time, in
# option.definitionsWithLocations.
{ lib }:
let
  # Values are rendered rather than emitted structurally. An option's value can
  # be a function, a derivation or a 40-entry keymap, none of which survive a
  # trip through JSON intact, and all of which a reader would rather see written
  # the way they would write it themselves.
  renderLimit = 8192;

  render =
    value:
    let
      attempt = builtins.tryEval (
        lib.generators.toPretty {
          multiline = true;
          allowPrettyValues = true;
        } value
      );
    in
    if !attempt.success then
      "<not representable>"
    else if lib.stringLength attempt.value > renderLimit then
      lib.substring 0 renderLimit attempt.value + "\n/* ... truncated ... */"
    else
      attempt.value;
in
rec {
  /**
    Collect everything one host sets, as a documentation record.

    Only options the flake itself declares are considered, and only definitions
    written inside the flake's own source are reported -- a module's internal
    `mkDefault` is a fact about the module, documented on the module's page, not
    a fact about the host.

    Definitions are kept one per file rather than merged, so shared policy
    (`hosts/common/workstation.nix`) stays distinguishable from what the host
    itself asked for.

    # Inputs

    `name`
    : The attribute name of the configuration, e.g. `framework-desktop`.

    `kind`
    : `nixos`, `home-manager` or `darwin`.

    `configuration`
    : The evaluated configuration, i.e. an entry of `self.nixosConfigurations`
      and friends.

    `optionPaths`
    : Location lists of the options the flake declares, as produced by
      [`optionPathsOf`](#function-library-lib.docs.optionPathsOf). Bounding the
      walk this way keeps it away from the many thousands of options nixpkgs and
      home-manager contribute, most of which are expensive and some of which
      throw when forced.

    `facts`
    : Dotted option paths to report by *value* rather than by definition, as
      things that are true of the machine.

      Some of what a configuration is built from never reaches the settings
      list, because the settings list is built from where a value was written
      and not everything has a usable "where". An identity passed straight into
      a configuration builder is the usual case: it is defined by an inline
      module, so the module system attributes it to whatever file it can find a
      position in -- for StewOS's `stewos.user` that is nixpkgs' own `flake.nix`
      on the NixOS side and `<unknown-file>` on the home-manager side. Neither
      is somewhere a reader could go look.

      Reading the merged value instead sidesteps provenance entirely, and has
      the property the settings list cannot offer here: a value handed to both
      halves of a machine reads identically on both their pages.

    `src`
    : The documented flake's source, normally `self.outPath`.

    # Type

    ```
    mkHost :: AttrSet -> AttrSet
    ```
  */
  mkHost =
    {
      name,
      kind,
      configuration,
      optionPaths,
      src,
      repoUrl,
      branch,
      facts ? [ ],
    }:
    let
      prefix = "${toString src}/";
      rel = f: lib.removePrefix prefix (toString f);
      isOurs = f: lib.hasPrefix prefix (toString f);

      # The flake's own modules are documented elsewhere; a definition coming
      # from one of them is a default, not a choice this host made.
      isConfiguration = f: isOurs f && !(lib.hasPrefix "modules/" (rel f));

      # Deliberately not lib.attrByPath. An option is itself an attrset, with
      # attributes named "default", "type", "value" and so on, so walking a
      # dotted path straight through one steps out of the option tree and into
      # the option's own internals -- where forcing an attribute means forcing
      # that option's default, which is how a lookup for a nested submodule key
      # ends up evaluating a package for the wrong platform.
      #
      # Stopping at the first option is also the right answer for the reader: a
      # host sets `settings` as one block, and that block is what it should be
      # shown having written.
      lookup =
        path:
        let
          go =
            attrs: rest:
            if rest == [ ] then
              (if lib.isOption attrs then attrs else null)
            else if !(lib.isAttrs attrs) || lib.isOption attrs || !(attrs ? ${lib.head rest}) then
              null
            else
              go attrs.${lib.head rest} (lib.tail rest);

          # Reaching an option can itself throw: an option tree is lazy, and the
          # attribute being forced may belong to a module that cannot be
          # evaluated for this host at all.
          attempt = builtins.tryEval (go configuration.options path);
        in
        if attempt.success then attempt.value else null;

      settingFor =
        path:
        let
          opt = lookup path;

          definitions = map (d: {
            file = rel d.file;
            url = "${repoUrl}/blob/${branch}/${rel d.file}";
            value = render d.value;
          }) (lib.filter (d: isConfiguration d.file) (opt.definitionsWithLocations or [ ]));

          # An option can be perfectly well documented and still refuse to be
          # evaluated on a particular host -- a package that does not exist for
          # its platform, a default that reads something the host never set.
          # That is a fact worth reporting, not a reason to lose the site.
          attempt = builtins.tryEval (builtins.deepSeq definitions definitions);
        in
        if opt == null then
          null
        else if !attempt.success then
          {
            name = lib.concatStringsSep "." path;
            definitions = [ ];
            error = "This option could not be evaluated for this host.";
          }
        else if attempt.value == [ ] then
          null
        else
          {
            name = lib.concatStringsSep "." path;
            definitions = attempt.value;
            error = null;
          };

      settings = lib.filter (s: s != null) (map settingFor optionPaths);

      # "Which modules is this host running" is the first question a reader has,
      # and it is answered by the enable flags rather than by the settings list:
      # a module enabled from a module's own default would otherwise go unseen.
      enabledFor =
        path:
        let
          opt = lookup path;
          value = builtins.tryEval (opt.value or false);
        in
        if opt != null && lib.last path == "enable" && value.success && value.value == true then
          [ (lib.concatStringsSep "." (lib.init path)) ]
        else
          [ ];

      modulesEnabled = lib.concatMap enabledFor optionPaths;

      # A fact is read from config rather than from options, so a path naming a
      # whole namespace -- stewos.user, which is five options and not one --
      # renders as the single record it is written as, which is how a reader
      # thinks of it.
      factFor =
        dotted:
        let
          path = lib.splitString "." dotted;
          attempt = builtins.tryEval (lib.attrByPath path null configuration.config);
          opt = lookup path;
        in
        if !attempt.success || attempt.value == null then
          null
        else
          {
            name = dotted;
            value = render attempt.value;
            description = opt.description or null;
          };

      hostFacts = lib.filter (f: f != null) (map factFor facts);

      # Every host answers these, under a different name each time.
      attr =
        path: default:
        let
          attempt = builtins.tryEval (lib.attrByPath path default configuration.config);
        in
        if attempt.success then attempt.value else default;

      # NixOS and nix-darwin both record the platform in config; a home
      # configuration only knows it through the package set it was given.
      system = attr [ "nixpkgs" "hostPlatform" "system" ] (
        configuration.pkgs.stdenv.hostPlatform.system or null
      );
    in
    {
      inherit
        name
        kind
        system
        modulesEnabled
        settings
        ;

      facts = hostFacts;

      stateVersion = toString (
        if kind == "home-manager" then
          attr [ "home" "stateVersion" ] ""
        else
          attr [ "system" "stateVersion" ] ""
      );

      # Where a reader should look to read the whole thing, rather than the
      # per-setting links: the files this host is actually written in.
      sources = lib.unique (
        lib.concatMap (
          s:
          map (d: {
            inherit (d) file url;
          }) s.definitions
        ) settings
      );
    };

  /**
    The location lists of every option in a set of option-set records, with the
    `<name>` placeholders nixosOptionsDoc emits for `attrsOf` submodules dropped.

    Those placeholders describe the *shape* of an option's value; they are not
    paths into an option tree and cannot be looked up in one.

    # Type

    ```
    optionPathsOf :: [AttrSet] -> [[String]]
    ```
  */
  optionPathsOf =
    sets:
    lib.unique (
      lib.concatMap (
        set:
        lib.filter (loc: !(lib.any (p: lib.hasPrefix "<" p) loc)) (
          lib.mapAttrsToList (_: o: o.loc) set.options
        )
      ) sets
    );
}
