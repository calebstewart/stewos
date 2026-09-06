# Status icons for the update-manager tray and its notifications.
#
# Deliberately a separate derivation from the daemon: the daemon takes the
# rendered tree by path at runtime (--icon-dir), so recolouring the set
# re-realizes only this runCommand. Baking it into the daemon instead would put
# the store path in that package's postFixup, and every recolour -- every host
# on a different colour scheme -- would recompile the Rust crate.
#
# Each colour is its own argument so a caller can change one without respelling
# the rest:
#
#   pkgs.stewos.update-manager-icons.override { error = "#ff0000"; }
#
# The SVG sources draw entirely in `currentColor`; a one-line stylesheet is what
# assigns the colour, which is why nothing here has to rewrite the sources. The
# building state's progress frames come out of the same stylesheet: one
# `stroke-dasharray` per frame on the bar's path, so the 21 frames are one SVG
# rendered 21 times rather than 21 sources to keep in step.
{
  lib,
  runCommand,
  resvg,

  idle ? "#9399b2",
  checking ? "#89b4fa",
  upToDate ? "#a6e3a1",
  updatesAvailable ? "#f9e2af",
  applying ? "#cba6f7",
  building ? "#94e2d5",
  error ? "#f38ba8",
  blocked ? "#fab387",

  # The tray menu's own glyphs. One neutral colour for all of them: these are
  # actions, so unlike the status icons they carry no meaning in their hue.
  menu ? "#cdd6f4",
}:
let
  # The building icon is rendered once per this many percent. The daemon
  # rounds its progress to the nearest frame; at 16px a finer step is invisible.
  progressStep = 5;

  # The baseline runs from x=4 to x=20: 16 user units. A frame at p % draws the
  # first 16*p/100 of it. Computed in tenths, which is exact for multiples of 5,
  # because resvg does not honour `pathLength` and the length must be absolute.
  frameCss =
    p:
    let
      tenths = p * 8 / 5;
    in
    "#progress { stroke-dasharray: ${toString (tenths / 10)}.${toString (lib.mod tenths 10)} 100; }";

  # Argument names are camelCase for the Nix side; `file` is the SVG stem and
  # the icon name the daemon looks up. This table is the only place the two
  # spellings meet. `source` is the SVG to render when it is not `file`, and
  # `extraCss` is appended to the colour stylesheet.
  status = [
    {
      file = "idle";
      color = idle;
    }
    {
      file = "checking";
      color = checking;
    }
    {
      file = "up-to-date";
      color = upToDate;
    }
    {
      file = "updates-available";
      color = updatesAvailable;
    }
    {
      file = "applying";
      color = applying;
    }
    # Rendered as the source stands it is the 0 % frame: the fallback when the
    # daemon wants the state without a fraction.
    {
      file = "building";
      color = building;
    }
    {
      file = "error";
      color = error;
    }
    {
      file = "blocked";
      color = blocked;
    }
  ]
  # building-000 … building-100, zero-padded so the daemon can format the name.
  ++ map (
    step:
    let
      p = step * progressStep;
    in
    {
      file = "building-${lib.fixedWidthNumber 3 p}";
      source = "building";
      color = building;
      extraCss = frameCss p;
    }
  ) (lib.range 0 (100 / progressStep));

  actions =
    map
      (file: {
        inherit file;
        color = menu;
      })
      [
        "search"
        "apply"
        "review"
        "report"
        "troubleshoot"
        "quit"
        "build"
        "cancel"
      ];

  # Freedesktop contexts: the state badges are Status, the menu glyphs are
  # Actions. Keeping them apart is what lets "checking" and "search" coexist.
  contexts = [
    {
      dir = "status";
      icons = status;
    }
    {
      dir = "actions";
      icons = actions;
    }
  ];

  allIcons = lib.concatMap (
    ctx:
    map (
      icon:
      {
        source = icon.file;
        extraCss = "";
      }
      // icon
      // {
        inherit (ctx) dir;
      }
    ) ctx.icons
  ) contexts;

  # 16-48 are what SNI hosts pick from for the tray; 64 is what the daemon
  # hands to the notification server.
  sizes = [
    16
    22
    24
    32
    48
    64
  ];

  stylesheet = icon: ''
    printf 'svg { color: %s; }\n%s\n' ${lib.escapeShellArg icon.color} ${lib.escapeShellArg icon.extraCss} \
      > "$stylesheets/${icon.file}.css"
  '';

  render =
    icon:
    lib.concatMapStringsSep "\n" (size: ''
      resvg --stylesheet "$stylesheets/${icon.file}.css" \
        --width ${toString size} --height ${toString size} \
        ${./. + "/${icon.source}.svg"} \
        "$out/share/icons/hicolor/${toString size}x${toString size}/${icon.dir}/stewos-update-${icon.file}.png"
    '') sizes;

  themeDirs = lib.concatMap (
    ctx: map (size: "${toString size}x${toString size}/${ctx.dir}") sizes
  ) contexts;
in
runCommand "stewos-update-manager-icons"
  {
    nativeBuildInputs = [ resvg ];
    passthru = {
      inherit sizes progressStep;
      colors = {
        inherit
          idle
          checking
          upToDate
          updatesAvailable
          applying
          building
          error
          blocked
          menu
          ;
      };
    };
    meta = {
      description = "Status and menu icons for the StewOS update manager tray";
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p ${lib.concatMapStringsSep " " (dir: "\"$out/share/icons/hicolor/${dir}\"") themeDirs}

    stylesheets=$(mktemp -d)
    ${lib.concatMapStringsSep "\n" stylesheet allIcons}

    ${lib.concatMapStringsSep "\n" render allIcons}

    cat > $out/share/icons/hicolor/index.theme <<'EOF'
    [Icon Theme]
    Name=Hicolor
    Comment=StewOS update manager icons
    Directories=${lib.concatStringsSep "," themeDirs}
    ${lib.concatMapStringsSep "\n" (
      ctx:
      lib.concatMapStringsSep "\n" (size: ''
        [${toString size}x${toString size}/${ctx.dir}]
        Size=${toString size}
        Context=${if ctx.dir == "status" then "Status" else "Actions"}
        Type=Fixed
      '') sizes
    ) contexts}
    EOF
  ''
