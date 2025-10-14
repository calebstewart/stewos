{hostname, stewos, ...}: {
  darwinConfigurations.${hostname} = stewos.lib.mkNixDarwinSystem {
    inherit hostname;

    system = "aarch64-darwin";
    modules = [./configuration.nix];
  };
}
