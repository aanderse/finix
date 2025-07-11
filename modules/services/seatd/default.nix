{ config, pkgs, lib, ... }:
let
  cfg = config.services.seatd;
in
{
  options.services.seatd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "seat";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups = lib.optionalAttrs (cfg.group == "seat") {
      seat = { };
    };

    finit.services.seatd = {
      description = "seat management daemon";
      runlevels = "34";
      conditions = "service/syslogd/ready";
      notify = "s6";
      command = "${pkgs.seatd.bin}/bin/seatd -n %n -u root -g ${cfg.group}" + lib.optionalString cfg.debug " -l debug";
    };

    synit.daemons.seatd = {
      argv = [
        "${pkgs.seatd.bin}/bin/seatd"
          "-n" "3"
          "-u" "root"
          "-g" cfg.group
      ] ++ lib.optionals cfg.debug [ "-l" "debug" ];
      readyOnNotify = 3;
      provides = [ [ "milestone" "login" ] ];
    };
  };
}
