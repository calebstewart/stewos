# The caelestia shell's colour scheme, derived from a base16 palette.
#
# Caelestia draws everything from Material 3 colour roles -- primary,
# surfaceContainer, onSurfaceVariant and so on -- which it reads from a
# scheme.json in its state directory. Its own CLI writes that file, from a
# built-in scheme or from the wallpaper. Where the CLI does not run, or where
# the shell should follow config.colorScheme with the rest of the desktop,
# this writes it instead.
#
# Base16 has sixteen colours and Material 3 has about sixty roles, so most
# roles are mixtures. The accents are the palette's own: blue (base0D) is
# primary, which is the accent every other StewOS theme uses, cyan (base0C)
# secondary and purple (base0E) tertiary. Surfaces are the background stepped
# towards the foreground, which keeps the palette's tint at every level and
# does not depend on what a scheme uses base01 to base04 for -- they are
# darker than the background in some schemes and lighter in others.
{ lib }:
let
  # "1e1e2e" -> [ 30 30 46 ]
  channels =
    hex:
    map (i: lib.fromHexString (builtins.substring i 2 hex)) [
      0
      2
      4
    ];

  toHex =
    n:
    let
      digits = lib.toLower (lib.toHexString n);
    in
    if n < 16 then "0${digits}" else digits;

  # Nix divides integers towards zero; a channel is never negative.
  round = x: builtins.floor (x + 0.5);

  # `amount` of the way from one colour to another, each channel on its own:
  # mix "000000" "ffffff" 0.5 is "808080". Colours are six hex digits with no
  # "#", as in a base16 palette.
  mix =
    from: to: amount:
    lib.concatStrings (
      lib.zipListsWith (a: b: toHex (round (a + (b - a) * amount))) (channels from) (channels to)
    );

  # "primary" -> "Primary", for the roles named after another: onPrimary.
  capitalise = s: lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;
in
{
  /**
    The contents of caelestia's scheme.json for a base16 palette, as an
    attribute set to pass to `builtins.toJSON`.

    # Inputs

    `name`
    : The scheme's name, which caelestia shows in its scheme picker.

    `palette`
    : The sixteen base16 colours, `base00` to `base0F`, as six hex digits
      each: `config.colorScheme.palette`.

    `variant`
    : `"dark"` (the default) or `"light"`. Decides which way the lowest
      surface steps away from the background.

    # Type

    ```
    mkScheme :: { name :: String, palette :: AttrSet, variant :: String } -> AttrSet
    ```

    # Examples

    ```nix
    builtins.toJSON (mkScheme {
      inherit (config.colorScheme) palette;
      name = config.colorScheme.slug;
    })
    ```
  */
  mkScheme =
    {
      name,
      palette,
      variant ? "dark",
    }:
    let
      p = palette;
      background = p.base00;
      foreground = p.base05;

      # The background, a fraction of the way to the foreground.
      surface = mix background foreground;

      # Text and marks that should recede: the foreground, part of the way
      # back to the background.
      muted = mix foreground background;

      # An accent and the three roles that go with it. Text on an accent is
      # the background colour, which is its opposite in light and dark alike;
      # a container is the background tinted with the accent, and text on that
      # is the accent brought towards the foreground.
      accent = role: colour: {
        ${role} = colour;
        "on${capitalise role}" = background;
        "${role}Container" = mix background colour 0.3;
        "on${capitalise role}Container" = mix colour foreground 0.6;
      };

      # The "fixed" roles keep one appearance in light and dark.
      fixed = role: colour: {
        "${role}Fixed" = mix colour foreground 0.6;
        "${role}FixedDim" = colour;
        "on${capitalise role}Fixed" = background;
        "on${capitalise role}FixedVariant" = mix background colour 0.3;
      };
    in
    {
      inherit name;
      flavour = "default";
      mode = if variant == "light" then "light" else "dark";

      colours = lib.mergeAttrsList [
        {
          primary_paletteKeyColor = p.base0D;
          secondary_paletteKeyColor = p.base0C;
          tertiary_paletteKeyColor = p.base0E;
          neutral_paletteKeyColor = surface 0.5;
          neutral_variant_paletteKeyColor = surface 0.5;

          inherit background;
          onBackground = foreground;

          surface = background;
          surfaceDim = background;
          surfaceBright = surface 0.18;
          # The one level below the background: darker in a dark scheme,
          # lighter in a light one.
          surfaceContainerLowest = mix background (if variant == "light" then "ffffff" else "000000") 0.25;
          surfaceContainerLow = surface 0.03;
          surfaceContainer = surface 0.06;
          surfaceContainerHigh = surface 0.1;
          surfaceContainerHighest = surface 0.15;
          onSurface = foreground;
          surfaceVariant = surface 0.2;
          onSurfaceVariant = muted 0.2;
          inverseSurface = foreground;
          inverseOnSurface = background;

          outline = muted 0.45;
          outlineVariant = surface 0.2;
          shadow = "000000";
          scrim = "000000";

          surfaceTint = p.base0D;
          inversePrimary = mix p.base0D background 0.45;
        }

        (accent "primary" p.base0D)
        (accent "secondary" p.base0C)
        (accent "tertiary" p.base0E)
        (accent "error" p.base08)
        (accent "success" p.base0B)

        (fixed "primary" p.base0D)
        (fixed "secondary" p.base0C)
        (fixed "tertiary" p.base0E)

        # The sixteen terminal colours, in the usual base16 arrangement.
        {
          term0 = p.base00;
          term1 = p.base08;
          term2 = p.base0B;
          term3 = p.base0A;
          term4 = p.base0D;
          term5 = p.base0E;
          term6 = p.base0C;
          term7 = p.base05;
          term8 = p.base03;
          term9 = p.base08;
          term10 = p.base0B;
          term11 = p.base0A;
          term12 = p.base0D;
          term13 = p.base0E;
          term14 = p.base0C;
          term15 = p.base07;
        }
      ];
    };
}
