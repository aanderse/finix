{ config, pkgs, lib, ... }:
let
  cfg = config.services.openssh;

  configFile = settingsFormat.generate "sshd.conf" cfg.settings;
  settingsFormat =
    let
      # reports boolean as yes / no
      mkValueString = v:
        if lib.isInt           v then toString v
        else if lib.isString   v then v
        else if true  ==   v then "yes"
        else if false ==   v then "no"
        else throw "unsupported type ${builtins.typeOf v}: ${(lib.generators.toPretty {}) v}";

      base = pkgs.formats.keyValue {
        mkKeyValue = k: v: "${k} ${mkValueString v}";
      };
      # OpenSSH is very inconsistent with options that can take multiple values.
      # For some of them, they can simply appear multiple times and are appended, for others the
      # values must be separated by whitespace or even commas.
      # Consult either sshd_config(5) or, as last resort, the OpehSSH source for parsing
      # the options at servconf.c:process_server_config_line_depth() to determine the right "mode"
      # for each. But fortunaly this fact is documented for most of them in the manpage.
      commaSeparated = [ "Ciphers" "KexAlgorithms" "Macs" ];
      spaceSeparated = [ "AuthorizedKeysFile" "AllowGroups" "AllowUsers" "DenyGroups" "DenyUsers" "HostKey" "Port" ];
    in {
      inherit (base) type;

      generate = name: value:
        let transformedValue = lib.mapAttrs (key: val:
          if lib.isList val then
            if lib.elem key commaSeparated then lib.concatStringsSep "," (map toString val)
            else if lib.elem key spaceSeparated then lib.concatStringsSep " " (map toString val)
            else throw "list value for unknown key ${key}: ${(lib.generators.toPretty {}) val}"
          else
            val
          ) value;
        in
          base.generate name transformedValue;
    };
in
{
  options.services.openssh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openssh;
    };

    sftp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      executable = lib.mkOption {
        type = lib.types.str;
      };

      flags = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
      };
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          AddressFamily = lib.mkOption {
            type = lib.types.enum [ "any" "inet" "inet6" ];
            default = "any";
            description = ''
              Specifies which address family should be used by sshd(8).
            '';
          };

          Banner = lib.mkOption {
            type = lib.types.either (lib.types.enum [ "none" ]) lib.types.path;
            default = "none";
            description = ''
              The contents of the specified file are sent to the remote user before authentication is
              allowed. If the argument is `none` then no banner is displayed.
            '';
          };

          HostKey = lib.mkOption {
            type = with lib.types; listOf path;
            default = [ ];
            description = "TODO: description";
          };

          LogLevel = lib.mkOption {
            type = lib.types.enum [ "QUIET" "FATAL" "ERROR" "INFO" "VERBOSE" "DEBUG" "DEBUG1" "DEBUG2" "DEBUG3" ];
            default = "INFO"; # upstream default
            description = ''
              Gives the verbosity level that is used when logging messages from sshd(8). Logging with a DEBUG level
              violates the privacy of users and is not recommended.
            '';
          };

          UsePAM =
            lib.mkEnableOption "PAM authentication"
            // { default = true; };

          PasswordAuthentication = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Specifies whether password authentication is allowed.
            '';
          };

          PermitRootLogin = lib.mkOption {
            default = "prohibit-password";
            type = lib.types.enum ["yes" "without-password" "prohibit-password" "forced-commands-only" "no"];
            description = ''
              Whether the root user can login using ssh.
            '';
          };

          Port = lib.mkOption {
            # type = with lib.types; coercedTo port lib.singleton (listOf port);
            type = with lib.types; listOf port;
            default = [ 22 ];
            description = ''
              Specifies the port number that sshd(8) listens on.
            '';
          };

          KbdInteractiveAuthentication = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Specifies whether keyboard-interactive authentication is allowed.
            '';
          };

          KexAlgorithms = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "sntrup761x25519-sha512@openssh.com"
              "curve25519-sha256"
              "curve25519-sha256@libssh.org"
              "diffie-hellman-group-exchange-sha256"
            ];
            description = ''
              Allowed key exchange algorithms

              Uses the lower bound recommended in both
              <https://stribika.github.io/2015/01/04/secure-secure-shell.html>
              and
              <https://infosec.mozilla.org/guidelines/openssh#modern-openssh-67>
            '';
          };
          Macs = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "hmac-sha2-512-etm@openssh.com"
              "hmac-sha2-256-etm@openssh.com"
              "umac-128-etm@openssh.com"
            ];
            description = ''
              Allowed MACs

              Defaults to recommended settings from both
              <https://stribika.github.io/2015/01/04/secure-secure-shell.html>
              and
              <https://infosec.mozilla.org/guidelines/openssh#modern-openssh-67>
            '';
          };
          StrictModes = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether sshd should check file modes and ownership of directories
            '';
          };
          Ciphers = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "chacha20-poly1305@openssh.com"
              "aes256-gcm@openssh.com"
              "aes128-gcm@openssh.com"
              "aes256-ctr"
              "aes192-ctr"
              "aes128-ctr"
            ];
            description = ''
              Allowed ciphers

              Defaults to recommended settings from both
              <https://stribika.github.io/2015/01/04/secure-secure-shell.html>
              and
              <https://infosec.mozilla.org/guidelines/openssh#modern-openssh-67>
            '';
          };
        };
      };
      default = { };
      description = "Configuration for `sshd_config(5)`.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh.sftp.executable = lib.mkDefault "${cfg.package}/libexec/sftp-server";
    services.openssh.settings = {
      # TODO: fixup host key generation
      HostKey = [ "/var/lib/sshd/ssh_host_ed25519_key" ];

      "Subsystem sftp" = lib.mkIf cfg.sftp.enable "${cfg.sftp.executable} ${lib.concatStringsSep " " cfg.sftp.flags}";
    };

    finit.tasks.ssh-keygen = {
      description = "generate ssh host keys";
      log = true;
      command = pkgs.writeShellScript "ssh-keygen.sh" ''
        if ! [ -s "/var/lib/sshd/ssh_host_ed25519_key" ]; then
          ${cfg.package}/bin/ssh-keygen -t ed25519 -f "/var/lib/sshd/ssh_host_ed25519_key" -N ""
        fi
      '';
    };

    finit.services.sshd = {
      description = "openssh daemon";
      conditions = [ "net/lo/up" "service/syslogd/ready" "task/ssh-keygen/success" ];
      notify = "pid";
      command = "${cfg.package}/bin/sshd -D -f /etc/ssh/sshd_config";
      cgroup.name = "user";
    };

    environment.etc."ssh/sshd_config".source = configFile;

    security.pam.services.sshd = lib.mkIf cfg.settings.UsePAM {
      text = ''
        # Account management.
        account required pam_unix.so debug # unix (order 10900)

        # Authentication management.
        auth sufficient pam_unix.so likeauth try_first_pass debug # unix (order 11500)
        auth required pam_deny.so debug # deny (order 12300)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt debug # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=0 debug # env (order 10100)
        session required pam_unix.so debug # unix (order 10200)

        ${lib.optionalString config.services.elogind.enable "session optional ${pkgs.elogind}/lib/security/pam_elogind.so"}
        ${lib.optionalString config.services.seatd.enable "session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so"}

        session required pam_loginuid.so debug # loginuid (order 10300)
      '';
    };

    # TODO: move this into programs.ssh maybe?
    environment.systemPackages = [
      cfg.package
    ];

    services.tmpfiles.sshd.rules = [
      "d /var/lib/sshd 0755"
    ];

    synit.daemons.sshd = {
      argv = let
        keygenScript = pkgs.execline.passthru.writeScript "ssh-keygen.el" "-s0" ''
          foreground { s6-mkdir -m 0755 -p /var/lib/sshd }
          foreground {
            if -n { eltest -s "/var/lib/sshd/ssh_host_ed25519_key" }
            ssh-keygen -t ed25519 -f "/var/lib/sshd/ssh_host_ed25519_key" -N ""
          }
          $@
        '';
      in [
        keygenScript
        "${cfg.package}/bin/sshd" "-D" "-e" "-f" "/etc/ssh/sshd_config"
      ];
      path = [ cfg.package ];
      provides = [ [ "milestone" "login" ] ];
      requires = [ { key = [ "milestone" "network" ]; } ];
    };

    users.users.sshd = {
      group = "sshd";
      description = "SSH privilege separation user";
    };

    users.groups = {
      sshd = { };
    };
  };
}
