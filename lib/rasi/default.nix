{ lib }:
rec {
  /**
    Check if the given value is a rasi literal, i.e. an attribute set carrying an
    `asRasiLiteral` attribute as produced by `mkLiteral`.

    # Type

    ```
    isLiteral :: Any -> Bool
    ```
  */
  isLiteral = v: (lib.isAttrs v) && ((lib.attrsets.attrByPath [ "asRasiLiteral" ] null v) != null);

  /**
    Check if the given value is a string in hex format.

    # Type

    ```
    isHex :: Any -> Bool
    ```
  */
  isHex = v: (lib.isString v) && ((builtins.match "[a-fA-F0-9]+" v) != null);

  /**
    Construct a Rasi literal value. When serialized to Rasi, this will be a literal string
    in the final file with no quotes or special formatting.

    Every constructor in this library -- colours, distances, gradients, keywords --
    ultimately returns one of these, so a literal is the common currency of the
    RASI DSL. Use it directly for any syntax the library does not wrap yet.

    # Type

    ```
    mkLiteral :: String -> Literal
    ```

    # Examples

    ```nix
    mkLiteral "bold"
    => { asRasiLiteral = "bold"; }

    toRASI { "*" = { font = mkLiteral "monospace 12"; }; }
    => "* {\n  font: monospace 12;\n}\n"
    ```
  */
  mkLiteral = value: {
    asRasiLiteral = value;
  };

  /**
    Construct a literal with multiple components from other values.

    Each part is rendered with `mkValueString` and the results joined with a
    single space, which is how RASI writes compound values such as padding,
    border widths and border styles. The `pad*`, `border*` and `borderStyle*`
    helpers are all thin wrappers over this.

    # Type

    ```
    mkMultiLiteral :: [Any] -> Literal
    ```

    # Examples

    ```nix
    mkMultiLiteral [ (pixels 4) (pixels 8) ]
    => { asRasiLiteral = "4px 8px"; }
    ```
  */
  mkMultiLiteral =
    parts: mkLiteral (lib.strings.concatStringsSep " " (lib.lists.forEach parts (v: mkValueString v)));

  /**
    Convert a given value to it's rasi string representation. If the value is a rasi literal
    created with `mkLiteral`, it will be serialized appropriately. Otherwise, the default
    `lib.generators.mkValueStringDefault` converter is used for base types.

    Lists become bracketed, comma-separated RASI lists; strings are quoted with
    newlines, quotes and backslashes escaped; and a bare integer is taken to mean
    pixels, so `padding = 8` and `padding = pixels 8` render the same.

    # Type

    ```
    mkValueString :: Any -> String
    ```

    # Examples

    ```nix
    mkValueString (mkLiteral "bold")  => "bold"
    mkValueString 8                   => "8px"
    mkValueString "hello"             => "\"hello\""
    mkValueString [ (mkLiteral "a") (mkLiteral "b") ] => "[a,b]"
    ```
  */
  mkValueString =
    v:
    let
      mkValueStringDefault = lib.generators.mkValueStringDefault { };
    in
    if isLiteral v then
      v.asRasiLiteral
    else if lib.isList v then
      "[" + (lib.strings.concatStringsSep "," (lib.lists.forEach v (item: mkValueString item))) + "]"
    else if lib.isString v then
      ''"${lib.strings.replaceStrings [ "\n" ''"'' "\\" ] [ "\\n" ''\t'' "\\\\" ] v}"''
    else if lib.isInt v then
      (pixels v).asRasiLiteral
    else
      mkValueStringDefault v;

  /**
    Construct a colour from a bare hexadecimal string -- no leading `#`, which
    this adds. Any length RASI accepts works (`RGB`, `RGBA`, `RRGGBB`,
    `RRGGBBAA`); aborts if the string contains anything but hex digits.

    Written to take the digits alone so a palette value from nix-colors can be
    passed straight through.

    # Type

    ```
    hexColor :: String -> Literal
    ```

    # Examples

    ```nix
    hexColor "1e1e2e"    => { asRasiLiteral = "#1e1e2e"; }
    hexColor config.colorScheme.palette.base00
    ```
  */
  hexColor =
    v:
    if isHex v then
      mkLiteral "#${v}"
    else
      abort "lib.rasi.hexColor: ${lib.generators.toPretty v}: must be a string matching [a-fA-F0-9]+";
  /**
    Construct an `rgb()` colour. Each component is rendered with `mkValueString`,
    so integers, `percent` values and other literals are all accepted.

    # Type

    ```
    rgb :: Any -> Any -> Any -> Literal
    ```

    # Examples

    ```nix
    rgb 30 30 46
    => { asRasiLiteral = "rgb(30px,30px,46px)"; }

    rgb (mkLiteral "30") (mkLiteral "30") (mkLiteral "46")
    => { asRasiLiteral = "rgb(30,30,46)"; }
    ```
  */
  rgb =
    r: g: b:
    mkLiteral "rgb(${mkValueString r},${mkValueString g},${mkValueString b})";
  /**
    Construct an `rgba()` colour. As with `rgb`, every component goes through
    `mkValueString`, so a bare integer renders as pixels -- wrap components in
    `mkLiteral` or `percent` when that is not what you want.

    # Type

    ```
    rgba :: Any -> Any -> Any -> Any -> Literal
    ```

    # Examples

    ```nix
    rgba (mkLiteral "30") (mkLiteral "30") (mkLiteral "46") (mkLiteral "0.8")
    => { asRasiLiteral = "rgba(30,30,46,0.8)"; }
    ```
  */
  rgba =
    r: g: b: a:
    mkLiteral "rgba(${mkValueString r},${mkValueString g},${mkValueString b},${mkValueString a})";

  /**
    The `transparent` colour keyword.
  */
  transparent = mkLiteral "transparent";

  /**
    Text style keywords, for RASI's `text-style` property: `bold`, `italic`,
    `underline`, `strikethrough` and `nostyle` (which renders as `none`).
  */
  bold = mkLiteral "bold";
  italic = mkLiteral "italic";
  underline = mkLiteral "underline";
  strikethrough = mkLiteral "strikethrough";
  nostyle = mkLiteral "none";

  /**
    Reference an image by path, as RASI's `url("...")`. Use `imgScale` to also
    give the scaling mode.

    # Type

    ```
    img :: (Path | String) -> Literal
    ```

    # Examples

    ```nix
    img ./wallpaper.png
    => { asRasiLiteral = ''url("/nix/store/...-wallpaper.png")''; }
    ```
  */
  img = path: mkLiteral ''url("${path}")'';

  /**
    Reference an image by path together with a scaling mode -- RASI's
    `url("...", mode)`. The mode is rendered with `mkValueString`, so pass it as
    a literal (`mkLiteral "both"`, `mkLiteral "width"`, `mkLiteral "height"`).

    # Type

    ```
    imgScale :: (Path | String) -> Any -> Literal
    ```

    # Examples

    ```nix
    imgScale ./wallpaper.png (mkLiteral "both")
    => { asRasiLiteral = ''url("/nix/store/...-wallpaper.png", both)''; }
    ```
  */
  imgScale = path: scale: mkLiteral ''url("${path}", ${mkValueString scale})'';

  /**
    Direction keywords, used by properties that take one: `left`, `right`, `up`
    and `down`.
  */
  left = mkLiteral "left";
  right = mkLiteral "right";
  up = mkLiteral "up";
  down = mkLiteral "down";

  /**
    Compass position keywords, for anchoring and window location: `northWest`,
    `north`, `northEast`, `east`, `southEast`, `south`, `southWest` and `west`.
    The corner names render with a space, e.g. `north west`.
  */
  northWest = mkLiteral "north west";
  north = mkLiteral "north";
  northEast = mkLiteral "north east";
  east = mkLiteral "east";
  southEast = mkLiteral "south east";
  south = mkLiteral "south";
  southWest = mkLiteral "south west";
  west = mkLiteral "west";

  /**
    Orientation keywords, for properties such as `orientation`: `horizontal` and
    `vertical`.
  */
  horizontal = mkLiteral "horizontal";
  vertical = mkLiteral "vertical";

  /**
    Construct an angle in radians from a float. Aborts on anything that is not a
    float -- write `1.0`, not `1`. See `degrees` for the same thing in degrees,
    and `angle` for a bare, unitless value.

    # Type

    ```
    radians :: Float -> Literal
    ```

    # Examples

    ```nix
    radians 1.57  => { asRasiLiteral = "1.570000rad"; }
    ```
  */
  radians =
    v: if lib.isFloat v then mkLiteral "${toString v}rad" else abort "lib.rasi.radians: expected float";
  /**
    Construct an angle in degrees from a float. Aborts on anything that is not a
    float -- write `90.0`, not `90`.

    # Type

    ```
    degrees :: Float -> Literal
    ```

    # Examples

    ```nix
    degrees 90.0  => { asRasiLiteral = "90.000000deg"; }
    ```
  */
  degrees =
    v: if lib.isFloat v then mkLiteral "${toString v}deg" else abort "lib.rasi.degrees: expected float";

  /**
    Construct a percentage. Accepts an int or a float and aborts outside
    `[0,100]`. Used both as a distance (a percentage of the parent) and as the
    argument to a named colour's `divide`.

    # Type

    ```
    percent :: (Int | Float) -> Literal
    ```

    # Examples

    ```nix
    percent 50            => { asRasiLiteral = "50%"; }
    colors.aliceblue.divide (percent 50)
    ```
  */
  percent =
    v:
    if ((lib.isFloat v) || (lib.isInt v)) && (v >= 0 && v <= 100) then
      mkLiteral "${toString v}%"
    else
      abort "lib.rasi.percent: expected value in [0,100]";
  /**
    Construct a bare, unitless number from a float, for the places RASI wants an
    angle with no suffix. Aborts on anything that is not a float.

    # Type

    ```
    angle :: Float -> Literal
    ```

    # Examples

    ```nix
    angle 0.5  => { asRasiLiteral = "0.500000"; }
    ```
  */
  angle =
    v: if lib.isFloat v then mkLiteral "${toString v}" else abort "lib.rasi.angle: must be a float";

  /**
    The named colours RASI understands, as an attribute set keyed by name
    (`colors.aliceblue`, `colors.rebeccapurple`, ...). The names come from
    `./named-colors.nix` and are all lower case.

    Each entry is a literal that also carries a `divide` function, RASI's
    `name / value` syntax for taking a fraction of a colour. `divide` renders its
    argument with `mkValueString`, so pass a `percent` rather than a bare integer
    -- a bare integer is read as pixels.

    # Type

    ```
    colors :: AttrSet
    ```

    # Examples

    ```nix
    colors.aliceblue
    => { asRasiLiteral = "aliceblue"; divide = <lambda>; }

    colors.aliceblue.divide (percent 50)
    => { asRasiLiteral = "aliceblue / 50%"; }
    ```
  */
  colors =
    let
      mkNamedColor = name: {
        asRasiLiteral = "${name}";
        divide = percent: mkLiteral "${name} / ${mkValueString percent}";
      };
    in
    lib.lists.foldl (
      acc: name:
      acc
      // {
        "${name}" = mkNamedColor name;
      }
    ) { } (import ./named-colors.nix);

  /**
    Line style keywords, for border styles: `dash` and `solid`.
  */
  dash = mkLiteral "dash";
  solid = mkLiteral "solid";

  /**
    Construct a RASI `calc()` expression from two operands and an operator. Both
    operands are rendered with `mkValueString`, so they may themselves be
    `calc()` literals and nest.

    The `calc*` helpers below are the named operators; reach for this directly
    only for an operator they do not cover.

    # Type

    ```
    mkDuoCalc :: Any -> String -> Any -> Literal
    ```

    # Examples

    ```nix
    mkDuoCalc (percent 100) "-" (pixels 20)
    => { asRasiLiteral = "calc(100% - 20px)"; }
    ```
  */
  mkDuoCalc =
    lhs: op: rhs:
    mkLiteral "calc(${mkValueString lhs} ${op} ${mkValueString rhs})";
  /**
    The named binary `calc()` operators, each `lhs -> rhs -> Literal` over
    `mkDuoCalc`: `calcSub` (`-`), `calcAdd` (`+`), `calcDiv` (`/`), `calcMul`
    (`*`), `calcMin`, `calcMax`, `calcFloor`, `calcCeil`, `calcRound` and
    `calcMod` (`modulo`).

    # Type

    ```
    calcSub :: Any -> Any -> Literal
    ```

    # Examples

    ```nix
    calcSub (percent 100) (pixels 20)
    => { asRasiLiteral = "calc(100% - 20px)"; }

    calcDiv (calcSub (percent 100) (pixels 20)) (mkLiteral "2")
    => { asRasiLiteral = "calc(calc(100% - 20px) / 2)"; }
    ```
  */
  calcSub = lhs: rhs: mkDuoCalc lhs "-" rhs;
  calcAdd = lhs: rhs: mkDuoCalc lhs "+" rhs;
  calcDiv = lhs: rhs: mkDuoCalc lhs "/" rhs;
  calcMul = lhs: rhs: mkDuoCalc lhs "*" rhs;
  calcMin = lhs: rhs: mkDuoCalc lhs "min" rhs;
  calcMax = lhs: rhs: mkDuoCalc lhs "max" rhs;
  calcFloor = lhs: rhs: mkDuoCalc lhs "floor" rhs;
  calcCeil = lhs: rhs: mkDuoCalc lhs "ceil" rhs;
  calcRound = lhs: rhs: mkDuoCalc lhs "round" rhs;
  calcMod = lhs: rhs: mkDuoCalc lhs "modulo" rhs;

  /**
    Distance constructors, one per RASI unit: `pixels` (`px`), `elements` (`em`),
    `characters` (`ch`) and `millimeters` (`mm`). See also `percent` for a
    distance relative to the parent.

    `pixels` is the unit `mkValueString` assumes for a bare integer, so
    `padding = 8` and `padding = pixels 8` produce the same output.

    # Type

    ```
    pixels :: (Int | Float) -> Literal
    ```

    # Examples

    ```nix
    pixels 8      => { asRasiLiteral = "8px"; }
    elements 1    => { asRasiLiteral = "1em"; }
    ```
  */
  pixels = value: mkLiteral "${toString value}px";
  elements = value: mkLiteral "${toString value}em";
  characters = value: mkLiteral "${toString value}ch";
  millimeters = value: mkLiteral "${toString value}mm";

  /**
    Construct a linear gradient function (for use where an image is required).

    # Inputs

    `directionOrAngle`
    : A direction keyword (`left`, `right`, `up`, `down`) or an angle
      (`degrees`, `radians`), or `null` (the default) to leave it to RASI.

    `stops`
    : List of `{ color, value }` stops, emitted in order as `color, value` pairs.

    # Type

    ```
    linearGradient :: { directionOrAngle :: (Literal | Null), stops :: [{ color :: Any, value :: Any; }] } -> Literal
    ```

    # Examples

    ```nix
    linearGradient {
      stops = [
        { color = colors.black; value = percent 0; }
        { color = colors.white; value = percent 100; }
      ];
    }
    => { asRasiLiteral = "linearGradient(black,0%,white,100%)"; }
    ```
  */
  linearGradient =
    {
      directionOrAngle ? null,
      stops,
    }:
    let
      stopArgs = lib.lists.foldl (
        acc: stop:
        acc
        ++ [
          (mkValueString stop.color)
          (mkValueString stop.value)
        ]
      ) [ ] stops;
      args =
        if directionOrAngle != null then [ (mkValueString directionOrAngle) ] ++ stopArgs else stopArgs;
    in
    mkLiteral ("linearGradient(" + (lib.strings.concatStringsSep "," args) + ")");

  /**
    Padding constructors, following RASI's CSS-style shorthand by arity:

    - `pad1 v` -- all four sides (the identity function, present for symmetry)
    - `pad2 topBottom leftRight`
    - `pad3 top leftRight bottom`
    - `pad4 top right bottom left`

    Each takes distance values (`pixels`, `elements`, `percent`, ...) and joins
    them with `mkMultiLiteral`.

    # Type

    ```
    pad2 :: Any -> Any -> Literal
    ```

    # Examples

    ```nix
    pad2 (pixels 4) (pixels 8)
    => { asRasiLiteral = "4px 8px"; }
    ```
  */
  pad1 = v: v;
  pad2 =
    topBottom: leftRight:
    mkMultiLiteral [
      topBottom
      leftRight
    ];
  pad3 =
    top: leftRight: bottom:
    mkMultiLiteral [
      top
      leftRight
      bottom
    ];
  pad4 =
    top: right: bottom: left:
    mkMultiLiteral [
      top
      right
      bottom
      left
    ];

  /**
    Border width constructors, the same shorthand-by-arity as the `pad*` family:

    - `border1 v` -- all four sides (identity, present for symmetry)
    - `border2 topBottom leftRight`
    - `border3 top leftRight bottom`
    - `border4 top right bottom left`

    Use the `borderStyle*` family to give each width a line style as well.

    # Type

    ```
    border2 :: Any -> Any -> Literal
    ```

    # Examples

    ```nix
    border4 (pixels 1) (pixels 0) (pixels 1) (pixels 0)
    => { asRasiLiteral = "1px 0px 1px 0px"; }
    ```
  */
  border1 = v: v;
  border2 =
    topBottom: leftRight:
    mkMultiLiteral [
      topBottom
      leftRight
    ];
  border3 =
    top: leftRight: bottom:
    mkMultiLiteral [
      top
      leftRight
      bottom
    ];
  border4 =
    top: right: bottom: left:
    mkMultiLiteral [
      top
      right
      bottom
      left
    ];
  /**
    Border constructors that pair each width with a line style (`solid`, `dash`),
    interleaved as RASI expects:

    - `borderStyle1 width style` -- all four sides
    - `borderStyle2 topBottom tbStyle leftRight lrStyle`
    - `borderStyle3 top tStyle leftRight lrStyle bottom bStyle`
    - `borderStyle4 top tStyle right rStyle bottom bStyle left lStyle`

    # Type

    ```
    borderStyle1 :: Any -> Any -> Literal
    ```

    # Examples

    ```nix
    borderStyle1 (pixels 2) solid
    => { asRasiLiteral = "2px solid"; }

    borderStyle2 (pixels 2) solid (pixels 0) dash
    => { asRasiLiteral = "2px solid 0px dash"; }
    ```
  */
  borderStyle1 =
    d: s:
    mkMultiLiteral [
      d
      s
    ];
  borderStyle2 =
    topBottom: tbStyle: leftRight: lrStyle:
    mkMultiLiteral [
      topBottom
      tbStyle
      leftRight
      lrStyle
    ];
  borderStyle3 =
    top: tStyle: leftRight: lrStyle: bottom: bStyle:
    mkMultiLiteral [
      top
      tStyle
      leftRight
      lrStyle
      bottom
      bStyle
    ];
  borderStyle4 =
    top: tStyle: right: rStyle: bottom: bStyle: left: lStyle:
    mkMultiLiteral [
      top
      tStyle
      right
      rStyle
      bottom
      bStyle
      left
      lStyle
    ];

  /**
    Indirection into a theme variable or the environment. Four constructors, in
    two pairs:

    - `var name` -- reference a theme variable, RASI's `@name`
    - `varDefault name default` -- the same, with a fallback: `var(name, default)`
    - `env name` -- reference an environment variable, RASI's `${name}`
    - `envDefault name default` -- the same, with a fallback: `env(name, default)`

    The fallback is rendered with `mkValueString`, so it may be any value this
    library produces.

    # Type

    ```
    varDefault :: String -> Any -> Literal
    ```

    # Examples

    ```nix
    var "background"                    => { asRasiLiteral = "@background"; }
    varDefault "background" (hexColor "1e1e2e")
    => { asRasiLiteral = "var(background, #1e1e2e)"; }
    ```
  */
  varDefault = name: default: mkLiteral "var(${name}, ${mkValueString default})";
  envDefault = name: default: mkLiteral "env(${name}, ${mkValueString default})";
  var = name: mkLiteral "@${name}";
  env = name: mkLiteral "$${${name}}";

  /**
    The `inherit` keyword, taking the property's value from the parent element.
    Named `inherited` because `inherit` is a Nix keyword.
  */
  inherited = mkLiteral "inherit";

  /**
    Cursor keywords, for the `cursor` property: `default`, `pointer` and `text`.
  */
  default = mkLiteral "default";
  pointer = mkLiteral "pointer";
  text = mkLiteral "text";

  /**
    The `none` keyword, for properties that can be switched off outright.
    `nostyle` is the same literal, named for the text-style group.
  */
  none = mkLiteral "none";

  /**
    Generate a RASI configuration file normally used with
    Rofi. This is the format used for configuration files
    and themes for rofi.

    The document is an attribute set of sections; each section is an attribute
    set of properties, whose values are rendered with `mkValueString`. Section
    names are emitted verbatim, so they carry rofi's own selector syntax
    (`"*"`, `"window"`, `"element selected.normal"`). Sections and properties
    are emitted in attribute order, which for an attribute set means sorted by
    name.

    # Type

    ```
    toRASI :: AttrSet -> String
    ```

    # Examples

    ```nix
    toRASI {
      "*" = {
        background-color = hexColor "1e1e2e";
        text-color = hexColor "cdd6f4";
      };
      "window" = {
        width = percent 40;
        padding = pad2 (pixels 8) (pixels 12);
      };
    }
    =>
    ''
      * {
        background-color: #1e1e2e;
        text-color: #cdd6f4;
      }
      window {
        padding: 8px 12px;
        width: 40%;
      }
    ''
    ```
  */
  toRASI =
    document:
    let
      mkKeyValue = k: v: "  ${k}: ${mkValueString v};";
      mkSectionValues =
        values:
        lib.attrsets.foldlAttrs (
          acc: k: v:
          acc ++ [ (mkKeyValue k v) ]
        ) [ ] values;
      mkSectionLines = name: values: [ "${name} {" ] ++ (mkSectionValues values) ++ [ "}" ];
      accLines =
        acc: name: values:
        acc ++ (mkSectionLines name values);
    in
    (lib.strings.concatStringsSep "\n" (lib.attrsets.foldlAttrs accLines [ ] document)) + "\n";
}
