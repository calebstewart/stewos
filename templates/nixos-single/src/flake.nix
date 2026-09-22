{
  description = "Personal NixOS / Home-Manager Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    stewos = {
      url = "github:calebstewart/stewos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, stewos, ... }:
    let
      hostname = "my-hostname";
      system = "x86_64-linux";

      user = {
        username = "yourname";
        fullname = "Your Name";
        email = "your.name@server.tld";

        # This is optional, but is used by some applications. Most noteably
        # is git, which will be configured to modify your default name and
        # email if the CWD is under `~/git/{name-of-alias}`. In this case,
        # all repos under `~/git/work`. Along with the email, you can
        # also override `.fullname` to conditionally set your full name.
        #
        # The name 'work' here is arbitrary and could be anything like
        # "foo" or "google" or the name of the business for which you work.
        aliases.work.email = "your.name@yourjob.tld";
      };

      # StewOS modules are written against StewOS's own flake inputs, and they
      # use them inside "imports", so they have to arrive as specialArgs. See
      # the comment on "moduleInputs" in the StewOS flake.
      specialArgs = {
        inputs = stewos.lib.moduleInputs;
      };

      # nixpkgs with the overlays the StewOS modules expect: its own package
      # scope (pkgs.stewos.*), and NUR, which the firefox module uses for
      # browser addons. This is the same pair StewOS applies to its own hosts.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          stewos.overlays.default
          stewos.lib.moduleInputs.nur.overlays.default
        ];
      };
    in
    {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        inherit pkgs specialArgs;

        modules = [
          stewos.nixosModules.default
          {
            networking.hostName = hostname;
            stewos.user = user;
          }
          ./hardware-configuration.nix
          ./configuration.nix
        ];
      };

      homeConfigurations."${user.username}@${hostname}" =
        stewos.lib.moduleInputs.home-manager.lib.homeManagerConfiguration
          {
            inherit pkgs;
            extraSpecialArgs = specialArgs;

            modules = [
              stewos.homeModules.default
              {
                home.username = user.username;
                home.homeDirectory = "/home/${user.username}";
                stewos.user = user;
              }
              ./home.nix
            ];
          };
    };
}
