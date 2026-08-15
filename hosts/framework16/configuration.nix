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

  # This is a laptop, so S4 is worth having. Nothing here needs to relax
  # security.protectKernelImage -- it already defaults to false, so
  # `nohibernate` is not on the command line. framework-desktop turns it on.
  systemd.sleep.settings.Sleep = {
    AllowHibernation = true;
    AllowSuspendThenHibernate = true;
    AllowHybridSleep = true;
  };
}
