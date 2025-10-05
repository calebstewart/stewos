{nixpkgs, ...}:
let
  lib = nixpkgs.lib;
in rec {
  # Check if the given value is a rasi literal
  isLiteral = v: (lib.isAttrs v) && ((lib.attrsets.attrByPath ["asRasiLiteral"] null v) != null);

  # Check if the given value is a string in hex format
  isHex = v: (lib.isString v) && ((builtins.match "[a-fA-F0-9]+" v) != null);

  # Construct a Rasi literal value. When serialized to Rasi, this will be a literal string
  # in the final file with no quotes or special formatting.
  mkLiteral = value: {
    asRasiLiteral = value;
  };

  # Construct a literal with multiple components from other values
  mkMultiLiteral = parts: mkLiteral (lib.strings.concatStringsSep " " (lib.lists.forEach parts (v: mkValueString v)));

  # Convert a given value to it's rasi string representation. If the value is a rasi literal
  # created with mkRasiLiteral, it will be serialized appropriately. Otherwise, the default
  # lib.generators.mkValueStringDefault converter is used for base types.
  mkValueString = v:
    let
      mkValueStringDefault = lib.generators.mkValueStringDefault {};
    in if isLiteral v then v.asRasiLiteral 
        else if lib.isList v then "[" + (lib.strings.concatStringsSep "," (lib.lists.forEach v (item: mkValueString item))) + "]"
        else if lib.isString v then ''"${lib.strings.replaceStrings ["\n" ''"'' "\\"] ["\\n" ''\t'' "\\\\"] v}"''
        else if lib.isInt v then (pixels v).asRasiLiteral
        else mkValueStringDefault v;

  # Color functions
  hexColor = v: if isHex v then mkLiteral "#${v}" else abort "lib.rasi.hexColor: ${lib.generators.toPretty v}: must be a string matching [a-fA-F0-9]+";
  rgb = r: g: b: mkLiteral "rgb(${mkValueString r},${mkValueString g},${mkValueString b})";
  rgba = r: g: b: a: mkLiteral "rgba(${mkValueString r},${mkValueString g},${mkValueString b},${mkValueString a})";
  transparent = mkLiteral "transparent";

  # Text Style values
  bold = mkLiteral "bold";
  italic = mkLiteral "italic";
  underline = mkLiteral "underline";
  strikethrough = mkLiteral "strikethrough";
  nostyle = mkLiteral "none";

  # Image functions
  img = path: mkLiteral ''url("${path}")'';
  imgScale = path: scale: mkLiteral ''url("${path}", ${mkValueString scale})'';

  # Direction literals
  left = mkLiteral "left";
  right = mkLiteral "right";
  up = mkLiteral "up";
  down = mkLiteral "down";

  # Position literals
  northWest = mkLiteral "north west";
  north = mkLiteral "north";
  northEast = mkLiteral "north east";
  east = mkLiteral "east";
  southEast = mkLiteral "south east";
  south = mkLiteral "south";
  southWest = mkLiteral "south west";
  west = mkLiteral "west";

  horizontal = mkLiteral "horizontal";
  vertical = mkLiteral "vertical";

  # Construct an angle from a floating point integer
  radians = v: if lib.isFloat v then mkLiteral "${toString v}rad" else abort "lib.rasi.radians: expected float";
  degrees = v: if lib.isFloat v then mkLiteral "${toString v}deg" else abort "lib.rasi.degrees: expected float";
  percent = v: if ((lib.isFloat v) || (lib.isInt v)) && (v >= 0 && v <= 100) then mkLiteral "${toString v}%" else abort "lib.rasi.percent: expected value in [0,100]";
  angle = v: if lib.isFloat v then mkLiteral "${toString v}" else abort "lib.rasi.angle: must be a float";

  # Expose the named colors, and an ability to divide them. Eg: `colors.AliceBlue` or `colors.AliceBlue.divide 50`
  colors = let
    mkNamedColor = name: {
      asRasiLiteral = "${name}";
      divide = percent: mkLiteral "${name} / ${mkValueString percent}";
    };
  in lib.lists.foldl (acc: name: acc // {
    "${name}" = mkNamedColor name;
  }) {} (import ./named-colors.nix);

  # Line styles
  dash = mkLiteral "dash";
  solid = mkLiteral "solid";

  # Numeric calculations
  mkDuoCalc = lhs: op: rhs: mkLiteral "calc(${mkValueString lhs} ${op} ${mkValueString rhs})";
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

  # Distance
  pixels = value: mkLiteral "${toString value}px";
  elements = value: mkLiteral "${toString value}em";
  characters = value: mkLiteral "${toString value}ch";
  millimeters = value: mkLiteral "${toString value}mm";

  # Construct a linear gradient function (for use where an image is required)
  linearGradient = {directionOrAngle ? null, stops}:
    let
      stopArgs = lib.lists.foldl (acc: stop: acc ++ [(mkValueString stop.color) (mkValueString stop.value)]) [] stops;
      args = if directionOrAngle != null then [mkValueString directionOrAngle] ++ stopArgs
              else stopArgs;
    in mkLiteral ("linearGradient(" + (lib.strings.concatStringsSep "," args) + ")");

  # Padding values
  pad1 = v: v;
  pad2 = topBottom: leftRight: mkMultiLiteral [topBottom leftRight];
  pad3 = top: leftRight: bottom: mkMultiLiteral [top leftRight bottom];
  pad4 = top: right: bottom: left: mkMultiLiteral [top right bottom left];

  # Border values
  border1 = v: v;
  border2 = topBottom: leftRight: mkMultiLiteral [topBottom leftRight];
  border3 = top: leftRight: bottom: mkMultiLiteral [top leftRight bottom];
  border4 = top: right: bottom: left: mkMultiLiteral [top right bottom left];
  borderStyle1 = d: s: mkMultiLiteral [d s];
  borderStyle2 = topBottom: tbStyle: leftRight: lrStyle: mkMultiLiteral [topBottom tbStyle leftRight lrStyle];
  borderStyle3 = top: tStyle: leftRight: lrStyle: bottom: bStyle: mkMultiLiteral [top tStyle leftRight lrStyle bottom bStyle];
  borderStyle4 = top: tStyle: right: rStyle: bottom: bStyle: left: lStyle: mkMultiLiteral [top tStyle right rStyle bottom bStyle left lStyle];

  varDefault = name: default: mkLiteral "var(${name}, ${mkValueString default})";
  envDefault = name: default: mkLiteral "env(${name}, ${mkValueString default})";
  var = name: mkLiteral "@${name}";
  env = name: mkLiteral "$${${name}}";

  inherited = mkLiteral "inherit";

  # Cursor Types
  default = mkLiteral "default";
  pointer = mkLiteral "pointer";
  text = mkLiteral "text";

  none = mkLiteral "none";

  /**
    Generate a RASI configuration file normally used with
    Rofi. This is the format used for configuration files
    and themes for rofi.
  */
  toRASI = document:
    let
      mkKeyValue = k: v: "  ${k}: ${mkValueString v};";
      mkSectionValues = values: lib.attrsets.foldlAttrs (acc: k: v: acc ++ [(mkKeyValue k v)]) [] values;
      mkSectionLines = name: values: ["${name} {"] ++ (mkSectionValues values) ++ ["}"];
      accLines = acc: name: values: acc ++ (mkSectionLines name values);
    in (lib.strings.concatStringsSep "\n" (lib.attrsets.foldlAttrs accLines [] document)) + "\n";
}
