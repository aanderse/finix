{ config, pkgs, lib, ... }:
let
  cfg = config.services.polkit;
in
{
  options.services.polkit = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.polkit;
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable debug logs from polkit. This is required in order to see log messages from rule definitions.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        /* Log authorization checks. */
        polkit.addRule(function(action, subject) {
          // Make sure to set { services.polkit.debug = true; } in configuration.nix
          polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
        });

        /* Allow any local user to do anything (dangerous!). */
        polkit.addRule(function(action, subject) {
          if (subject.local) return "yes";
        });
      '';
      description = ''
        Any polkit rules to be added to config (in JavaScript ;-). See:
        <https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html#polkit-rules>
      '';
    };

    adminIdentities = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "unix-group:wheel" ];
      example = [
        "unix-user:alice"
        "unix-group:admin"
      ];
      description = ''
        Specifies which users are considered “administrators”, for those
        actions that require the user to authenticate as an
        administrator (i.e. have an `auth_admin`
        value).  By default, this is all users in the `wheel` group.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      cfg.package.bin
      cfg.package.out
    ];

    finit.services.polkit = {
      description = "policykit authorization manager";
      # TODO: conditions
      command = "${cfg.package.out}/lib/polkit-1/polkitd " + (lib.optionalString (!cfg.debug) "--no-debug");
    };

    # The polkit daemon reads action/rule files
    environment.pathsToLink = [ "/share/polkit-1" ];

    # PolKit rules for NixOS.
    environment.etc."polkit-1/rules.d/10-nixos.rules".text = ''
      polkit.addAdminRule(function(action, subject) {
        return [${lib.concatStringsSep ", " (map (i: "\"${i}\"") cfg.adminIdentities)}];
      });

      ${cfg.extraConfig}
    ''; # TODO: validation on compilation (at least against typos)

    services.dbus.packages = [ cfg.package.out ];

    security.pam.services.polkit-1 = {
      text = ''
        # Account management.
        account required pam_unix.so # unix (order 10900)

        # Authentication management.
        auth sufficient pam_unix.so likeauth try_first_pass # unix (order 11600)
        auth required pam_deny.so # deny (order 12400)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=0 # env (order 10100)
        session required pam_unix.so # unix (order 10200)
        session required pam_limits.so # conf=/nix/store/mibdlp1bmk4wl2qjk77i6fl1dg4kq6k6-limits.conf # limits (order 12200)
      '';
    };

    security.wrappers = {
      pkexec = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${cfg.package.bin}/bin/pkexec";
      };
      polkit-agent-helper-1 = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${cfg.package.out}/lib/polkit-1/polkit-agent-helper-1";
      };
    };

    users.users.polkituser = {
      description = "PolKit daemon";
      uid = config.ids.uids.polkituser;
      group = "polkituser";
    };

    users.groups.polkituser = { };
  };
}
