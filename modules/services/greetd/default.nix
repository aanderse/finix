{ config, pkgs, lib, ... }:
let
  cfg = config.services.greetd;
  format = pkgs.formats.toml { };

  configFile = format.generate "greetd.toml" cfg.settings;
in
{
  options.services.greetd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    settings = lib.mkOption {
      description = ''
        Contents of the greetd configuration file.
        See the greetd(5) man page.
      '';
      type = format.type;
    };
  };

  config = lib.mkIf cfg.enable {

    services.greetd.settings = {
      terminal.vt = lib.mkDefault "next";
      default_session = {
        command = lib.mkDefault "${pkgs.greetd.greetd}/bin/agreety";
        user = "greeter";
      };
    };

    finit.services.greetd = {
      description = "greeter daemon";
      runlevels = "34";
      conditions = [ "service/syslogd/ready" ] ++ lib.optionals config.services.seatd.enable [ "service/seatd/ready" ];
      command = "${pkgs.greetd.greetd}/bin/greetd --config ${configFile}";
      cgroup.name = "user";
    };

    synit.daemons.greetd = {
      argv = [ "${pkgs.greetd.greetd}/bin/greetd" "--config" configFile ];
      provides = [ [ "milestone" "login" ] ];
      requires = [ { key = [ "milestone" "wrappers" ]; } ]
        ++ lib.optional config.services.seatd.enable
          { key = [ "daemon" "seatd" ]; state = "ready"; };
    };

    users.users = {
      greeter = {
        isSystemUser = true;
        group = "greeter";
        extraGroups = lib.optionals config.services.seatd.enable [
          config.services.seatd.group
          "video"
        ];
      };
    };

    users.groups = {
      greeter = { };
    };

    services.tmpfiles.greetd.rules = [
      "d /var/cache/tuigreet - greeter greeter"
    ];

    security.pam = {
      enable = true;
      services.greetd.text = ''
        # Account management.
        account required pam_unix.so # unix (order 10900)

        # Authentication management.
        auth sufficient pam_unix.so likeauth nullok try_first_pass # unix (order 12800)
        auth required pam_deny.so # deny (order 13600)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=0 # env (order 10100)
        session required pam_unix.so # unix (order 10200)
        session required pam_loginuid.so # loginuid (order 10300)
      ''
      + lib.optionalString config.services.elogind.enable
        "session optional ${pkgs.elogind}/lib/security/pam_elogind.so"
      + lib.optionalString config.services.seatd.enable
        "session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so"
      ;
    };

  };
}
