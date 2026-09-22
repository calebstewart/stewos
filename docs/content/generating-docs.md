# How this site is generated

The generator is two halves with a JSON document between them.

`lib/docs/` evaluates the flake and writes everything it finds to one
`docs.json`: the option trees, the packages, the hosts, the flake's outputs and
inputs, and the library's doc-comments. `pkgs/flakedoc/` is a Rust program that
reads that document and writes HTML.

The split is the point. Evaluating a flake is slow, needs the flake's own
inputs, and only Nix can do it; rendering HTML is none of those things. Keeping a
serialized document in between means the renderer can be worked on without
re-evaluating anything, and a flake that cannot be evaluated on one machine can
be evaluated on several and merged — `flakedoc build` takes any number of
`--input` files.

```console
$ nix build .#docs
$ nix run nixpkgs#miniserve -- result
```

Both halves read `docs/flakedoc.toml`: the Nix half takes the list of module
trees and library namespaces to extract, and `flakedoc` takes the title, the
navigation order and the theme.

## Three things worth knowing before changing it

**Module trees are evaluated against a machine that does not exist.** A module
tree cannot be evaluated on its own — `modules/nixos/default.nix` imports stylix,
which probes for options that only a real evaluation declares — so each tree goes
through its real evaluator with a synthetic host. Pointing it at one of the real
hosts instead would work, and would be wrong: an option whose default reads
`config` would then be documented with that host's value rather than its own
default. `stewos.looking-glass.kvmfr.owner` documented itself as `"caleb"` for
exactly this reason during development.

**Options are recognised by where they were declared, not by their name.** An
option belongs to this flake when one of its declarations is a file inside it.
That needs no configuration, cannot be confused by a third-party module sharing a
namespace, and catches options declared *outside* the `stewos.*` namespace —
which matters, because the nix-darwin tree declares `programs.nh` and nothing
else at all.

It has one blind spot. A module imported as a value rather than as a path —
`imports = [ inputs.foo.homeManagerModules.default ]` — has no file of its own,
so the module system credits its options to the importing file. Those options
then look like this flake's own, and nothing downstream can tell the difference.

The remedy is at the import, not in the generator: give it a file back, which
fixes the module's error messages at the same time.

```nix
imports = [
  {
    _file = "${inputs.foo}/nix/hm-module.nix";
    imports = [ inputs.foo.homeManagerModules.default ];
  }
];
```

`excludeOptions` in `flakedoc.toml` is the fallback for an import you do not
control.

**The host pages are the reference's worked examples.** They are built from
`option.definitionsWithLocations`, keeping one entry per defining file rather
than merging them, so shared policy stays visibly distinct from what a machine
asked for itself. Definitions coming from `modules/` are dropped: a module's own
`mkDefault` is a fact about the module, and it is already documented on the
module's page.
