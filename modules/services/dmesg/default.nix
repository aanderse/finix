{ config, lib, pkgs, ... }:

let
  cfg = config.services.dmesg;
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    types
    ;
in
{
  options = {
    services.dmesg = {
      enable = mkOption {
        description = ''
          Disable printing of kernel messages
          to the console and enable dmesg
          running as a dedicated service.
        '';
        type = types.bool;
        default = false;
      };
      extraArgs = mkOption {
        description = ''
          List of command-line options to pass
          to the dmesg service.
        '';
        type = with types; listOf str;
        default = [ ];
      };
    };
  };

  config = mkIf cfg.enable {

    synit.daemons.dmesg = {
      argv = [
        # Disable printing to console.
        "foreground" "dmesg" "--console-off" ""
        "dmesg" "--follow"
      ] ++ cfg.extraArgs;
      path = [ pkgs.util-linux ];
      logging.args = mkDefault [
        "n1" # Single archive.
      ];
    };

  };
}
