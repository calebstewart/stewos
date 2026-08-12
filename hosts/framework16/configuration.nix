{
  inputs,
  ...
}:
{
  imports = [
    ../common/workstation.nix
    inputs.nixos-hardware.nixosModules.framework-16-7040-amd
  ];

  # The NixOS release this machine was first installed from. Per-machine on
  # purpose: it must not follow whatever the shared modules were written for.
  # DO NOT CHANGE.
  system.stateVersion = "24.05";
}
