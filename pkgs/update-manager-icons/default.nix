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
# assigns the colour, which is why nothing here has to rewrite the sources.
{
  lib,
  runCommand,
  resvg,

  idle ? "#9399b2",
  checking ? "#89b4fa",
  upToDate ? "#a6e3a1",
  updatesAvailable ? "#f9e2af",
  applying ? "#cba6f7",
  error ? "#f38ba8",

  # The tray menu's own glyphs. One neutral colour for all of them: these are
  # actions, so unlike the status icons they carry no meaning in their hue.
  menu ? "#cdd6f4",
}:
let
  # Argument names are camelCase for the Nix side; `file` is the SVG stem and
  # the icon name the daemon looks up. This table is the only place the two
  # spellings meet.
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
    {
      file = "error";
      color = error;
    }
  ];

  actions =
    map
      (file: {
        inherit file;
        color = menu;
      })
      [
        "search"
        "apply"
        "report"
        "troubleshoot"
        "quit"
      ];

  # Freedesktop contexts: the six state badges are Status, the menu glyphs are
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

  allIcons = lib.concatMap (ctx: map (icon: icon // { inherit (ctx) dir; }) ctx.icons) contexts;

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
    printf 'svg { color: %s; }\n' ${lib.escapeShellArg icon.color} \
      > "$stylesheets/${icon.file}.css"
  '';

  render =
    icon:
    lib.concatMapStringsSep "\n" (size: ''
      resvg --stylesheet "$stylesheets/${icon.file}.css" \
        --width ${toString size} --height ${toString size} \
        ${./. + "/${icon.file}.svg"} \
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
      inherit sizes;
      colors = {
        inherit
          idle
          checking
          upToDate
          updatesAvailable
          applying
          error
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
