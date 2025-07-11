{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.console;

  mkBinaryKeyMap = km: pkgs.runCommand "bkeymap"
    {
      nativeBuildInputs = [ pkgs.buildPackages.kbd ];
      preferLocalBuild = true;
    } ''
      loadkeys --bkeymap "${km}" >$out
    '';
in
{
  options = {
    hardware.console = {
      enable = lib.mkOption {
        description = "Whether to configure the console at boot.";
        type = lib.types.bool;
        default = true;
      };

      setvesablank = lib.mkOption {
        description = "Turn VESA screen blanking on or off.";
        type = lib.types.bool;
        default = true;
      };

      keyMap = lib.mkOption {
        description = ''
          The keyboard mapping table for the virtual consoles.
          This option may have no effect if
          hardware.console.binaryKeyMap is set.
        '';
        type = with lib.types; either str path;
        example = "us";
        # Not setting a default here can be obnoxious but
        # not worse than favoring a culturally biased
        # layout optimised for mechanical typewriters.
        # We should localize the templates and auto-detected
        # configs instead of the defaults.
      };

      binaryKeyMap = lib.mkOption {
        description = ''
          Binary keymap file.
          If unset then this is generated from
          the hardware.console.keyMap option.
        '';
        type = lib.types.path;
        default = mkBinaryKeyMap cfg.keyMap;
        defaultText = "Binary form of hardware.console.keyMap.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.kbd ] ;

    # Include binary keymap in the initramfs.
    boot.initrd.contents = [ { source = cfg.binaryKeyMap; } ];

    # Use the device-manager to load the keymap rather
    # than injecting somewhere into the early boot script.
    services.mdevd.coldplugRules =
      "-console 0:${toString config.ids.gids.tty} 600 +redirfd -r 0 ${cfg.binaryKeyMap} loadkmap";

    services.udev.packages = [ (pkgs.writeTextDir "etc/udev/rules.d/loadkmap" ''
      KERNEL=="console", SUBSYSTEM=="tty", RUN+="${pkgs.busybox}/bin/loadkmap <${cfg.binaryKeyMap}"
    '') ];

    system.activation.scripts.console = ''
      ${pkgs.kbd}/bin/setvesablank ${if cfg.setvesablank then "on" else "off"}
    '';
  };

  imports = [
    (lib.mkRenamedOptionModule [ "console" ] [ "hardware" "console" ])
  ];
}
