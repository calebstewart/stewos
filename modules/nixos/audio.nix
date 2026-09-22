{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stewos.audio;
  noise = cfg.noiseCancellation;
in
{
  options.stewos.audio = {
    enable = lib.mkEnableOption "audio";

    noiseCancellation = {
      enable = lib.mkEnableOption "microphone noise cancellation";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.rnnoise-plugin;
        defaultText = lib.literalExpression "pkgs.rnnoise-plugin";
        description = ''
          Package providing the noise suppressor as a LADSPA plugin at
          `lib/ladspa/librnnoise_ladspa.so`, exporting the
          `noise_suppressor_mono` and `noise_suppressor_stereo` labels.
        '';
      };

      channels = lib.mkOption {
        type = lib.types.enum [
          "mono"
          "stereo"
        ];
        default = "mono";
        description = ''
          Channel layout the filter runs at, which is also the layout
          applications see. A microphone carries voice, so `mono` is normally
          right; a stereo capture device is downmixed into it.
        '';
      };

      vadThreshold = lib.mkOption {
        type = lib.types.numbers.between 0.0 99.0;
        default = 50.0;
        description = ''
          Voice activity threshold, as a percentage. Raising it suppresses more
          background noise at the cost of clipping quiet speech.
        '';
      };

      gracePeriod = lib.mkOption {
        type = lib.types.ints.between 0 1000;
        default = 500;
        description = ''
          Milliseconds of audio to keep passing after voice activity stops, so
          the tail of a word is not cut off. This is the plugin's own default
          and costs no latency: it only holds the gate open for longer.
        '';
      };

      retroactiveGracePeriod = lib.mkOption {
        type = lib.types.ints.between 0 200;
        default = 0;
        description = ''
          Milliseconds of buffered audio to keep from before voice activity is
          detected, so the start of a word survives the detector's own delay.
          The plugin defaults this to 100; it is 0 here because the buffer is
          added straight to the latency of every capture path on the machine.
        '';
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "Noise Canceling Source";
        description = "Name the filtered source is shown under in mixers.";
      };
    };
  };

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

    # Enable XDG Sound Themes support
    xdg.sounds.enable = true;

    # An rnnoise filter chain in front of the microphone, applied to every
    # recording application rather than selected per-app.
    #
    # It is a WirePlumber *smart filter* (`filter.smart`, no
    # `filter.smart.target`), which is what makes it system-wide without being
    # the default source. WirePlumber inserts a targetless smart filter between
    # the default device and any stream that has not named a target of its own,
    # so `wpctl set-default` still picks the microphone -- the filter follows
    # it -- and an application that deliberately asks for a specific device
    # still gets that device unfiltered. Making the filter the default source
    # instead would work, but then the microphone choice would no longer be
    # expressible: the filter's own capture side is the thing that reads the
    # default source.
    #
    # The nodes carry an explicit `node.link-group`, which the module would
    # otherwise generate from its pid. WirePlumber keys a filter's identity off
    # that group and it is what stops the capture side from being linked back
    # to the source it feeds.
    services.pipewire.extraConfig.pipewire."99-noise-cancellation" = lib.mkIf noise.enable {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";

          # This is loaded into the session's PipeWire daemon, so a plugin that
          # fails to load must not take audio down with it.
          flags = [ "nofail" ];

          args = {
            "node.description" = noise.description;
            "media.name" = noise.description;

            "filter.graph".nodes = [
              {
                type = "ladspa";
                name = "rnnoise";
                # Absolute path: the search-path form appends ".so" and looks
                # through LADSPA_PATH, which the daemon does not have.
                plugin = "${noise.package}/lib/ladspa/librnnoise_ladspa.so";
                label = "noise_suppressor_${noise.channels}";
                control = {
                  "VAD Threshold (%)" = noise.vadThreshold;
                  "VAD Grace Period (ms)" = noise.gracePeriod;
                  "Retroactive VAD Grace (ms)" = noise.retroactiveGracePeriod;
                };
              }
            ];

            # rnnoise is trained at 48 kHz. Pinning the rate here resamples at
            # the edges of the filter rather than feeding it the device's rate.
            "audio.rate" = 48000;
            "audio.position" =
              if noise.channels == "mono" then
                [ "MONO" ]
              else
                [
                  "FL"
                  "FR"
                ];

            "capture.props" = {
              "node.name" = "effect_input.rnnoise";
              "node.link-group" = "rnnoise";
              "node.passive" = true;
            };

            "playback.props" = {
              "node.name" = "effect_output.rnnoise";
              "node.link-group" = "rnnoise";
              "media.class" = "Audio/Source";
              "filter.smart" = true;
              "filter.smart.name" = "rnnoise";
              # Also let it be picked explicitly, so an application that wants
              # the filtered source by name can have it.
              "filter.smart.targetable" = true;
            };
          };
        }
      ];
    };
  };
}
