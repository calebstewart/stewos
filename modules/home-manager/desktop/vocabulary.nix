# The vocabulary the desktop option surface is typed against.
#
# A plain attrset, not a module: ./options.nix builds its enums from these
# lists and ./default.nix validates bindings against them, and the two must not
# be allowed to drift apart.
{
  # Modifier names usable in a binding. The global prefix is added separately,
  # see "bindings.<name>.useModifier".
  modifiers = [
    "shift"
    "ctrl"
    "alt"
    "super"
  ];

  # Everything a binding can ask the window manager to do. Not every backend
  # implements every action; one that cannot says so at build time, naming the
  # binding and listing the actions it does support.
  #
  # Window-directional and monitor-directional actions are deliberately
  # separate. They sit on the same keys on Linux and macOS but are not the same
  # operation: on Linux (and Windows) the tiling that matters happens inside a
  # workspace, while on macOS the interesting axis is which display has focus.
  actions = [
    # Windows
    "close-window"
    "minimize-window"
    "fullscreen"
    "toggle-floating"
    "toggle-split-direction"
    "layout-accordion"
    "focus-window" # + direction
    "focus-next-window"
    "focus-previous-window"
    "move-window" # + direction
    "promote-window"
    "resize-grow"
    "resize-shrink"

    # Stacks: windows sharing one tile, shown one at a time
    "stack-window" # + direction
    "unstack-window"
    "stack-next"
    "stack-previous"

    # Monitors
    "focus-monitor" # + direction
    "focus-next-monitor"
    "move-window-to-monitor" # + direction
    "move-window-to-next-monitor"
    "move-workspace-to-next-monitor"

    # Workspaces. "move" follows the window there; "send" stays put.
    "workspace" # + workspace
    "workspace-next"
    "workspace-previous"
    "move-window-to-workspace" # + workspace
    "move-window-to-next-workspace"
    "move-window-to-previous-workspace"
    "send-window-to-workspace" # + workspace
    "workspace-back-and-forth"
    "move-window-back-and-forth"

    # Session and shell
    "launcher"
    "terminal"
    "lock-session"
    "volume-up"
    "volume-down"
    "volume-mute"
    "brightness-up"
    "brightness-down"
    "screenshot-region"
    "screenshot-screen"

    # The desktop's own machinery
    "reload-window-manager"
    "reload-hotkeys"
    "show-shortcuts"
  ];

  directions = [
    "left"
    "right"
    "up"
    "down"
  ];

  # Platforms a binding can be restricted to; one per backend directory.
  platforms = [
    "linux"
    "darwin"
    "windows"
  ];

  # Actions that are meaningless without their extra argument. Checked by an
  # assertion rather than expressed in the type, so the message can name the
  # offending binding instead of pointing at a submodule.
  directionalActions = [
    "focus-window"
    "move-window"
    "stack-window"
    "focus-monitor"
    "move-window-to-monitor"
  ];

  workspaceActions = [
    "workspace"
    "move-window-to-workspace"
    "send-window-to-workspace"
  ];
}
