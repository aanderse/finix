{ config, pkgs, lib, ... }:
let
  cfg = config.services.sysklogd;
in
{
  options.services.sysklogd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    finit.services.syslogd = {
      description = "system logging daemon";
      runlevels = "S0123456789";
      conditions = lib.optionals config.services.udev.enable [ "run/udevadm:5/success" ] ++ lib.optionals config.services.mdevd.enable [ "run/coldplug/success" ];
      command = "${pkgs.sysklogd}/bin/syslogd -F";
    };

    environment.etc."syslog.conf".source = "${pkgs.sysklogd}/share/doc/sysklogd/syslog.conf";
  };
}
