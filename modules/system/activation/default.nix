{ config, pkgs, lib, ... }:
let
  scriptOpts = {
    options = {
      deps = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "List of dependencies. The script will run after these.";
      };
      text = lib.mkOption {
        type = lib.types.lines;
        description = "The content of the script.";
      };
    };
  };
in
{
  options.system.activation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    scripts = lib.mkOption {
      type = with lib.types; attrsOf (coercedTo str lib.noDepEntry (submodule scriptOpts));
      default = {};

      example = lib.literalExpression ''
        { stdio.text =
          '''
            # Needed by some programs.
            ln -sfn /proc/self/fd /dev/fd
            ln -sfn /proc/self/fd/0 /dev/stdin
            ln -sfn /proc/self/fd/1 /dev/stdout
            ln -sfn /proc/self/fd/2 /dev/stderr
          ''';
        }
      '';

      description = ''
        A set of shell script fragments that are executed when a NixOS
        system configuration is activated.  Examples are updating
        /etc, creating accounts, and so on.  Since these are executed
        every time you boot the system or run
        {command}`nixos-rebuild`, it's important that they are
        idempotent and fast.
      '';
    };

    path = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
    };

    out = lib.mkOption {
      type = lib.types.path;
      description = "the actual script to run on activation....";
      readOnly = true;
    };
  };

  config = {
    system.activation.out =
      let
        set' = lib.mapAttrs (a: v:
          v // {
            text = ''
              #### Activation script snippet ${a}:
              _localstatus=0
              ${v.text}

              if (( _localstatus > 0 )); then
                printf "Activation script snippet '%s' failed (%s)\n" "${a}" "$_localstatus"
              fi
            '';
          }
        ) config.system.activation.scripts;
      in
        pkgs.writeScript "activate" ''
          #!${pkgs.runtimeShell}

          systemConfig='@systemConfig@'

          export PATH=/empty
          for i in ${toString config.system.activation.path}; do
              PATH=$PATH:$i/bin:$i/sbin
          done

          _status=0
          trap "_status=1 _localstatus=\$?" ERR

          # Ensure a consistent umask.
          umask 0022

          ${lib.textClosureMap lib.id set' (lib.attrNames set')}

          # Make this configuration the current configuration.
          # The readlink is there to ensure that when $systemConfig = /system
          # (which is a symlink to the store), /run/current-system is still
          # used as a garbage collection root.
          ln -sfn "$(readlink -f "$systemConfig")" /run/current-system

          exit $_status
        '';

    system.activation.scripts.specialfs = ''
      echo "specialfs stub here..."
      mkdir -p /bin /etc /run /tmp /usr /var
    '';

    system.activation.path = with pkgs; map lib.getBin [
      coreutils
      gnugrep
      findutils
      getent
      stdenv.cc.libc # nscd in update-users-groups.pl
      shadow
      nettools # needed for hostname
      util-linux # needed for mount and mountpoint
    ];
  };
}
