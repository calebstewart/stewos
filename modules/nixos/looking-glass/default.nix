{ ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.stewos.looking-glass;

  # Generate the looking-glass-client configuration where boolean values
  # are encoded as "yes" or "no".
  generateConfig =
    settings:
    lib.generators.toINI {
      mkKeyValue = lib.generators.mkKeyValueDefault {
        mkValueString =
          v:
          if (true == v) then
            "yes"
          else if (false == v) then
            "no"
          else
            (lib.generators.mkValueStringDefault { } v);
      } "=";
    } settings;
in
{
  options.stewos.looking-glass = {
    enable = lib.mkEnableOption "looking-glass";

    # Allow the user to override the looking-glass-client package
    package = lib.mkOption {
      description = "Package providing the looking-glass-client";
      type = lib.types.package;

      # By default, we install B6 because nixpkgs provides B7 which is broken for me
      # However, we also need to apply a patch which isn't even released in B7-rc1
      # yet which enables Looking Glass to run in Wayland with fractional scaling.
      default = pkgs.looking-glass-client.overrideAttrs {
        version = "B6";

        src = pkgs.fetchFromGitHub {
          owner = "gnif";
          repo = "LookingGlass";
          rev = "B6";
          hash = "sha256-6vYbNmNJBCoU23nVculac24tHqH7F4AZVftIjL93WJU=";
          fetchSubmodules = true;
        };

        patches = [ ./patches/0001-client-wayland-Let-viewporter-use-full-wl_buffer.patch ];
      };
    };

    # Options for using the KVM Frame Relay Kernel Module
    kvmfr = {
      enable = lib.mkEnableOption "kvmfr";

      owner = lib.mkOption {
        description = "Owner of the kvmfr device file(s)";
        default = config.stewos.user.username;
        type = lib.types.str;
      };

      group = lib.mkOption {
        description = "Group of the kvmfr device file(s)";
        default = "kvm";
        type = lib.types.str;
      };

      # package = lib.mkOption {
      #   description = "Package providing the looking-glass KVM frame-relay kernel module";
      #   default = config.boot.kernelPackages.kvmfr;
      #   type = lib.types.package;
      # };

      sizeMB = lib.mkOption {
        description = "Size (in megabytes) of the frame-relay device (see: https://looking-glass.io/docs/B6/install/#determining-memory)";
        default = 32;
        type = lib.types.ints.positive;
      };

      # This option should normally be left as true, but it will add a block to
      # virtualisation.libvirtd.qemu.verbatimConfig which will set the
      # 'cgroup_device_acl' setting to the standard list of devices along with
      # /dev/kvmfr0. This is normally what you want, but if you already have
      # a custom setting for this field, then you should disable this option,
      # ensure you add /dev/kvmfr0 yourself elsewhere otherwise your VM will
      # fail to start with a Permission Denied error.
      configureLibvirtCgroupACLs = lib.mkOption {
        description = "Whether to set the 'cgroup_device_acl' configuration for libvirt to allow kvmfr access";
        default = true;
        type = lib.types.bool;
      };
    };

    # Options for creating the /dev/shm shared memory file
    shm = {
      enable = lib.mkEnableOption "Shared Memory File";

      owner = lib.mkOption {
        description = "Owner of the shared memory file";
        default = "kvm";
        type = lib.types.str;
      };

      name = lib.mkOption {
        description = "Name of the shared memory file under /dev/shm";
        default = "looking-glass";
      };
    };

    # Client configuration (written to /etc/looking-glass-client.ini)
    settings = lib.mkOption {
      description = "Looking Glass client configuration";
      default = { };
      type = lib.types.submodule ./types/config;
    };
  };

  config = lib.mkIf cfg.enable {
    # Install looking glass
    environment.systemPackages = [ cfg.package ];

    # Optionally install the kvmfr kernel module
    boot.extraModulePackages = lib.lists.optional cfg.kvmfr.enable config.boot.kernelPackages.kvmfr;

    # Create the configuration file if requested
    environment.etc = {
      # Write the looking glass configuration
      "looking-glass-client.ini".text = generateConfig cfg.settings;

      # Set the frame size if kvmfr is enabled
      "modprobe.d/kvmfr.conf" = {
        enable = cfg.kvmfr.enable;
        text = ''
          options kvmfr static_size_mb=${builtins.toString cfg.kvmfr.sizeMB}
        '';
      };

      # Load the kvmfr module at boot if enabled
      "modules-load.d/kvmfr.conf" = {
        enable = cfg.kvmfr.enable;
        text = ''
          # KVMFR Looking Glass Module
          kvmfr
        '';
      };
    };

    # Automatically apply permissions to the kvmfr device as requested
    services.udev.packages = lib.lists.optional cfg.kvmfr.enable (
      pkgs.writeTextFile {
        name = "99-kvmfr.rules";
        destination = "/etc/udev/rules.d/99-kvmfr.rules";
        text = ''
          SUBSYSTEM=="kvmfr", OWNER="${cfg.kvmfr.owner}", GROUP="${cfg.kvmfr.group}", MODE="0660"
        '';
      }
    );

    # Create the /dev/shm file if requested
    systemd.tmpfiles.rules = lib.lists.optional cfg.shm.enable ''
      f /dev/shm/${cfg.shm.name} 0660 ${cfg.shm.owner} qemu-libvirtd -
    '';

    # Allow access to the kvmfr device from the libvirt cgroups
    virtualisation.libvirtd.qemu.verbatimConfig =
      lib.strings.optionalString (cfg.kvmfr.enable && cfg.kvmfr.configureLibvirtCgroupACLs)
        ''
          cgroup_device_acl = [
            "/dev/null", "/dev/full", "/dev/zero",
            "/dev/random", "/dev/urandom",
            "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
            "/dev/rtc","/dev/hpet", "/dev/vfio/vfio",
            "/dev/kvmfr0"
          ]
        '';

    # Add libvirt-qemu apparmor policy allowing rw access to kvmfr device
    security.apparmor.packages =
      lib.lists.optional (cfg.kvmfr.enable && config.security.apparmor.enable)
        (
          pkgs.writeTextFile {
            name = "libvirt-qemu-apparmor";
            destination = "/etc/apparmor.d/local/abstractions/libvirt-qemu";
            text = ''
              # Looking Glass
              /dev/kvmfr0 rw,
            '';
          }
        );
  };
}
