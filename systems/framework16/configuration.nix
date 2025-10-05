{...}: rec {
  stewos = {
    audio.enable = true;
    desktop-services.enable = true;
    greeter.enable = false;
    zsa.enable = false;
    virtualisation.enable = true;
    sshd.enable = true;
    looking-glass.enable = false;

    containers = {
      enable = true;
      enableCompose = true;
      enableDockerCompatability = true;
    };

    user = {
      username = "caleb";
      fullname = "Caleb Stewart";
    };
  };

  # Enable embedded home-manager
  home-manager.users.${stewos.user.username} = import ./home.nix;
}

