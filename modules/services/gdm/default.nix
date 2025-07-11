# FIXME: currently a work in progress, does not run
{ config, pkgs, lib, ... }:
let
  cfg = config.services.gdm;

  format = pkgs.formats.ini { };
in
{
  options.services.gdm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.gdm.settings = {
      daemon = {
        WaylandEnable = true;
      };

      debug = {
        Enable = true;
      };
    };

    environment.etc."gdm/custom.conf".source = format.generate "custom.conf" cfg.settings;

    services.dbus.packages = [ pkgs.gdm ];
    # FIXME: services.udev.packages = [ pkgs.gdm ];

    finit.services.gdm = {
      description = "gdm daemon";
      runlevels = "34";
      conditions = [ "service/syslogd/ready" ] ++ lib.optionals config.services.elogind.enable [ "service/elogind/ready" ];
      command = "${pkgs.gdm}/bin/gdm";
    };

    users.users.gdm = {
      name = "gdm";
      uid = config.ids.uids.gdm;
      group = "gdm";
      home = "/run/gdm";
      description = "GDM user";
    };

    users.groups.gdm = {
      gid = config.ids.gids.gdm;
    };

    services.tmpfiles.gdm.rules = [ ];

    security.pam.services.gdm-launch-environment = {
      text = ''
        auth     required       pam_succeed_if.so audit quiet_success user = gdm
        auth     optional       pam_permit.so

        account  required       pam_succeed_if.so audit quiet_success user = gdm
        account  sufficient     pam_unix.so

        password required       pam_deny.so

        session  required       pam_succeed_if.so audit quiet_success user = gdm
        session  required       pam_env.so readenv=0
        session  optional       ${pkgs.elogind}/lib/security/pam_elogind.so
        session  optional       pam_keyinit.so force revoke
        session  optional       pam_permit.so
      '';
    };

    security.pam.services.gdm-password = {
      text = ''
        auth      substack      login
        account   include       login
        password  substack      login
        session   include       login
      '';
    };
  };
}
