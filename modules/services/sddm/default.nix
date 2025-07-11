{ config, pkgs, lib, ... }:
let
  cfg = config.services.sddm;

  format = pkgs.formats.ini { };
  configFile = format.generate "sddm.conf" cfg.settings;
in
{
  options.services.sddm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
      example = {
        Autologin = {
          User = "john";
          Session = "plasma.desktop";
        };
      };
      description = ''
        Extra settings merged in and overwriting defaults in sddm.conf.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    services.sddm.settings = {
      General = {
        HaltCommand = "/run/current-system/sw/bin/loginctl poweroff";
        RebootCommand = "/run/current-system/sw/bin/loginctl reboot";
        Numlock = "none";

        # Implementation is done via pkgs/applications/display-managers/sddm/sddm-default-session.patch
        DefaultSession = ""; # optionalString (config.services.displayManager.defaultSession != null) "${config.services.displayManager.defaultSession}.desktop";

        DisplayServer = "x11";
      };
      X11 = {
        # MinimumVT = 7;
        ServerPath = "${pkgs.xorg.xorgserver.out}/bin/X";
        XephyrPath = "${pkgs.xorg.xorgserver.out}/bin/Xephyr";
        SessionCommand = "${pkgs.kdePackages.sddm}/share/sddm/scripts/Xsession";
        SessionDir = "${pkgs.openbox}/share/xsessions"; # "${dmcfg.sessionData.desktops}/share/xsessions";
        XauthPath = "${pkgs.xorg.xauth}/bin/xauth";
        # DisplayCommand = toString Xsetup;
        # DisplayStopCommand = toString Xstop;
        # EnableHiDPI = cfg.enableHidpi;

        # Path to the user session log file
        SessionLogFile = ".local/share/sddm/xorg-session.log";

        ServerArguments = "-logverbose 6 -xkbdir ${config.services.xserver.xkb.dir} -terminate -verbose 7";
      };
    };

    services.tmpfiles.sddm.rules = [
      # Home dir of the sddm user, also contains state.conf
      "d       /var/lib/sddm   0750    sddm    sddm"
      # This contains X11 auth files passed to Xorg and the greeter
      "d       /run/sddm       0711    root    root"
      # Sockets for IPC
      "r      /tmp/sddm-auth*" # TODO: r!
      # xauth files passed to user sessions
      "r      /tmp/xauth_*" # TODO: r!
      # "r!" above means to remove the files if existent (r), but only at boot (!).
      # tmpfiles.d/tmp.conf declares a periodic cleanup of old /tmp/ files, which
      # would ordinarily result in the deletion of our xauth files. To prevent that
      # from happening, explicitly tag these as X (ignore).
      "X       /tmp/sddm-auth*"
      "X       /tmp/xauth_*"
    ];

    services.dbus.packages = [ pkgs.kdePackages.sddm ];

    environment.systemPackages = [
      pkgs.kdePackages.sddm
    ];

    environment.etc."sddm.conf".source = configFile;
    environment.pathsToLink = [
      "/share/sddm"
    ];

    finit.services.sddm = {
      description = "sddm display manager";
      runlevels = "34";
      conditions = [ "service/syslogd/ready" "services/elogind/ready" ];
      command = "/run/current-system/sw/bin/sddm";
    };

    users.users.sddm = {
      home = "/var/lib/sddm";
      group = "sddm";
      uid = config.ids.uids.sddm;
    };

    users.groups = {
      sddm.gid = config.ids.gids.sddm;
    };

    security.pam.services = {
      sddm.text = ''
        auth      substack      login
        account   include       login
        password  substack      login
        session   include       login
      '';

      sddm-greeter.text = ''
        auth     required       pam_succeed_if.so audit quiet_success user = sddm
        auth     optional       pam_permit.so

        account  required       pam_succeed_if.so audit quiet_success user = sddm
        account  sufficient     pam_unix.so

        password required       pam_deny.so

        session  required       pam_succeed_if.so audit quiet_success user = sddm
        session  required       pam_env.so readenv=0
        session  optional       ${pkgs.elogind}/lib/security/pam_elogind.so
        session  optional       pam_keyinit.so force revoke
        session  optional       pam_permit.so
      '';

      sddm-autologin.text = ''
        auth     requisite pam_nologin.so
        auth     required  pam_succeed_if.so uid >= ${toString 0} quiet
        auth     required  pam_permit.so

        account  include   sddm

        password include   sddm

        session  include   sddm
      '';
    };
  };
}
