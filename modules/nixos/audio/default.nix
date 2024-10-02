{lib, config, pkgs, ...}:
let
  cfg = config.stewos.audio;
in {
  options.stewos.audio.enable = lib.mkEnableOption "audio";

  config = lib.mkIf cfg.enable {
    # Enable realtime scheduling for audio processing
    security.rtkit.enable = true;

    # Enable the pipewire audio service
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      jack.enable = true;

      alsa = {
        enable = true;
        support32Bit = true;
      };
    };

    # Enable NoiseTorch for noise cancellation
    programs.noisetorch.enable = true;
  };
}
