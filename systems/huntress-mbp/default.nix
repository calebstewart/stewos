{hostname, stewos, ...}: {
  nixosConfigurations.${hostname} = stewos.lib.mkNixDarwinSystem {
    inherit hostname;

    system = "aarch64-darwin";
    modules = [./configuration.nix];
  };
}
