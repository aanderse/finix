{ config, pkgs, lib, ... }:
let
  cfg = config.services.lemurs;

  format = pkgs.formats.toml { };
  configFile = format.generate "config.toml" cfg.settings;
in
{
  options.services.lemurs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.lemurs;
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.lemurs.settings = {
      tty = 7;

      # TODO: sync with pam environment variables
      initial_path = "${config.security.wrapperDir}:/run/current-system/sw/bin";

      pam_service = "lemurs";

      power_controls = {
        base_entries = [
          {
            # The text in the top-left to display how to shutdown.
            hint = "Shutdown";

            # The color and modifiers of the hint in the top-left corner
            hint_color = "dark gray";
            hint_modifiers = "";

            # The key used to shutdown. Possibilities are F1 to F12.
            key = "F1";
            # The command that is executed when the key is pressed
            cmd = "${config.finit.package}/bin/initctl poweroff";
          }

          {
            # The text in the top-left to display how to reboot.
            hint = "Reboot";

            # The color and modifiers of the hint in the top-left corner
            hint_color = "dark gray";
            hint_modifiers = "";

            # The key used to reboot. Possibilities are F1 to F12.
            key = "F2";
            # The command that is executed when the key is pressed
            cmd = "${config.finit.package}/bin/initctl reboot";
          }
        ];
      };

      wayland.wayland_sessions_path = "/etc/wayland-sessions";
    };

    security.pam.services.${cfg.settings.pam_service} = {
      text = ''
        # Account management.
        account required pam_unix.so # unix (order 10900)

        # Authentication management.
        auth optional pam_unix.so likeauth nullok # unix-early (order 11500)
        auth sufficient pam_unix.so likeauth nullok try_first_pass # unix (order 12800)
        auth required pam_deny.so # deny (order 13600)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=1 debug # env (order 10100)
        session required pam_unix.so # unix (order 10200)
        # https://github.com/coastalwhite/lemurs/issues/166
        session optional pam_loginuid.so # loginuid (order 10300)
        # session optional ${pkgs.elogind}/lib/security/pam_elogind.so debug # need this i think
        session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so
        session required ${pkgs.linux-pam}/lib/security/pam_lastlog.so silent # lastlog (order 10700)
      '';
    };

    environment.etc."lemurs/config.toml".source = configFile;

    finit.services.lemurs = {
      description = "lemurs terminal user interface display/login manager";
      runlevels = "34";
      conditions = "service/syslogd/ready";
      command = "${pkgs.util-linux}/bin/agetty -nil ${cfg.package}/bin/lemurs tty${toString cfg.settings.tty}";
      cgroup.name = "user";
    };
  };
}
