# Package extraction.
#
# Read from the flake's evaluated "packages" output rather than from the files
# under pkgs/. A package that wraps an upstream derivation inherits that
# derivation's meta without restating it, so the file says nothing while the
# evaluated attribute says everything.
{ lib }:
let
  # meta is a convention, not a schema. Nothing here may assume a field exists,
  # and every read goes through tryEval: meta.license on a package whose
  # licenses list is built from a lookup can throw, and one bad package must not
  # take the whole site down with it.
  try =
    default: value:
    let
      attempt = builtins.tryEval value;
    in
    if attempt.success then attempt.value else default;

  # A license is one of: an attrset, a list of them, or a bare string (which
  # nixpkgs still permits and a handful of packages still use).
  licenses =
    value:
    let
      one =
        l:
        if lib.isString l then
          {
            spdxId = null;
            fullName = l;
            url = null;
            free = null;
          }
        else
          {
            spdxId = l.spdxId or null;
            fullName = l.fullName or (l.shortName or null);
            url = l.url or null;
            free = l.free or null;
          };
    in
    map one (lib.toList value);
in
{
  /**
    Describe one entry of a flake's `packages` output.

    # Inputs

    `attr`
    : The attribute name the package is exposed under.

    `drv`
    : The derivation itself.

    `src`
    : The documented flake's source, normally `self.outPath`.

    `packageDir`
    : Source-relative directory the flake keeps its package definitions in. A
      package is linked there when `meta.position` points outside the flake,
      which is what happens when a definition overrides an upstream derivation
      and inherits its meta along with its provenance.

    # Type

    ```
    mkPackage :: AttrSet -> AttrSet
    ```
  */
  mkPackage =
    {
      attr,
      drv,
      system,
      src,
      repoUrl,
      branch,
      packageDir ? "pkgs",
    }:
    let
      prefix = "${toString src}/";
      meta = drv.meta or { };

      # meta.position is "<file>:<line>"; only the file is wanted, and only when
      # it is one of ours.
      position = try null (meta.position or null);
      positionFile = if position == null then null else lib.head (lib.splitString ":" position);

      declared =
        if positionFile != null && lib.hasPrefix prefix positionFile then
          lib.removePrefix prefix positionFile
        else if builtins.pathExists "${src}/${packageDir}/${attr}" then
          "${packageDir}/${attr}"
        else
          null;
    in
    {
      inherit attr system;

      pname = try null (drv.pname or null);
      version = try null (drv.version or null);
      name = try attr (drv.name or attr);

      description = try null (meta.description or null);
      longDescription = try null (meta.longDescription or null);
      homepage = try null (meta.homepage or null);
      mainProgram = try null (meta.mainProgram or null);
      platforms = try [ ] (meta.platforms or [ ]);
      broken = try false (meta.broken or false);
      unfree = try false (meta.unfree or false);
      licenses = try [ ] (licenses (meta.license or [ ]));
      outputs = try [ "out" ] (drv.outputs or [ "out" ]);

      source =
        if declared == null then
          null
        else
          {
            name = declared;
            url = "${repoUrl}/blob/${branch}/${declared}";
          };
    };
}
