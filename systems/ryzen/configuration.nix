{...}: rec {
  stewos = {
    audio.enable = true;
    desktop-services.enable = true;
    greeter.enable = true;
    zsa.enable = true;
    virtualisation.enable = true;
    sshd.enable = true;

    containers = {
      enable = true;
      enableCompose = true;
      enableDockerCompatability = true;
    };

    looking-glass = {
      enable = true;

      kvmfr = {
        enable = true;
        sizeMB = 128;
      };

      settings = {
        app.shmFile = "/dev/kvmfr0";
        input.escapeKey = "KEY_RIGHTCTRL";
        
        win = {
          fullScreen = true;
          noScreensaver = true;
          showFPS = true;
        };
      };
    };

    user = {
      username = "caleb";
      fullname = "Caleb Stewart";
    };
  };

  # Enable embedded home-manager
  home-manager.users.${stewos.user.username} = import ./home.nix;
}
