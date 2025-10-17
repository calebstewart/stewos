{
  mkRofiTheme,
  stewos,
  inputs,
  colorScheme ? inputs.nix-colors.colorSchemes.catppuccin-mocha,
}:
let
  palette = colorScheme.palette;
in
mkRofiTheme {
  name = "stewos.rasi";

  settings = with stewos.lib.rasi; {
    "*" = {
      background = hexColor palette.base00;
      background-alt = hexColor palette.base01;
      foreground = hexColor palette.base05;
      selected = hexColor palette.base06;
      active = hexColor palette.base03;
      urgent = hexColor palette.base08;
    };

    window = {
      enabled = true;
      transparency = "real";
      location = north;
      anchor = north;
      fullscreen = false;
      width = percent 50;
      x-offset = pixels 0;
      y-offset = pixels 0;
      margin = pixels 0;
      padding = pixels 0;
      border = borderStyle1 (pixels 3) solid;
      border-radius = pixels 15;
      border-color = var "background-alt";
      background-color = var "background";
      cursor = default;
    };

    mainbox = {
      enabled = true;
      spacing = pixels 20;
      margin = pixels 0;
      padding = pixels 40;
      border = borderStyle1 (pixels 0) solid;
      border-radius = pixels 0;
      border-color = var "selected";
      background-color = transparent;
      children = [
        "inputbar"
        "listview"
      ];
    };

    inputbar = {
      enabled = true;
      spacing = pixels 10;
      margin = pixels 0;
      padding = pixels 12;
      border = border4 0 0 0 (pixels 4);
      border-radius = border4 0 (percent 100) (percent 100) 0;
      border-color = var "selected";
      background-color = var "background-alt";
      text-color = var "foreground";
      children = [
        "prompt"
        "entry"
      ];
    };

    prompt = {
      enabled = true;
      background-color = inherited;
      text-color = inherited;
    };

    textbox-prompt-colon = {
      enabled = true;
      expand = false;
      str = "::";
      background-color = inherited;
      text-color = inherited;
    };

    entry = {
      enabled = true;
      background-color = inherited;
      text-color = inherited;
      cursor = text;
      placeholder = "Search";
      placeholder-color = inherited;
    };

    listview = {
      enabled = true;
      cycle = true;
      dynamic = true;
      scrollbar = false;
      layout = horizontal;
      reverse = false;
      fixed-height = false;
      fixed-columns = false;
      spacing = pixels 10;
      margin = 0;
      padding = 0;
      border = borderStyle1 0 solid;
      border-radius = 0;
      border-color = var "selected";
      background-color = transparent;
      text-color = var "foreground";
      cursor = default;
    };

    scrollbar = {
      handle-width = pixels 5;
      handle-color = var "selected";
      border-radius = 0;
      background-color = var "background-alt";
    };

    element = {
      enabled = true;
      spacing = pixels 10;
      margin = 0;
      padding = pad2 (pixels 15) (pixels 10);
      border = borderStyle1 (pixels 0) solid;
      border-radius = 0;
      border-color = var "selected";
      background-color = transparent;
      text-color = var "foreground";
      orientation = vertical;
      cursor = pointer;
    };

    "element normal.normal" = {
      background-color = transparent;
      text-color = var "foreground";
    };

    "element selected.normal" = {
      border = border4 0 0 0 (pixels 4);
      border-radius = 0;
      border-color = var "selected";
      background-color = var "background-alt";
      text-color = var "foreground";
    };

    element-icon = {
      background-color = transparent;
      text-color = inherited;
      size = pixels 64;
      cursor = inherited;
    };

    element-text = {
      background-color = transparent;
      text-color = inherited;
      highlight = inherited;
      cursor = inherited;
      vertical-align = 0.5;
      horizontal-align = 0.5;
    };

    error-message = {
      padding = pixels 40;
      border = borderStyle1 0 solid;
      border-radius = 0;
      border-color = var "selected";
      background-color = colors.black.divide (percent 10);
      text-color = var "foreground";
    };

    textbox = {
      background-color = transparent;
      text-color = var "foreground";
      vertical-align = 0.5;
      horizontal-align = 0.0;
      highlight = none;
    };
  };
}
