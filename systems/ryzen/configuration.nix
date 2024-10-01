{...}: {
  stewos = {
    greeter.enable = true;
    zsa.enable = true;

    containers = {
      enable = true;
      enableCompose = true;
      enableDockerCompatability = true;
    };

    looking-glass = {
      enable = true;

      kvmfr = {
        enable = true;
        owner = "caleb";
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

    users.caleb.enable = true;
  };
}
