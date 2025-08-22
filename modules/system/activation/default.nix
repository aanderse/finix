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
  checkAssertWarn = lib.asserts.checkAssertWarn config.assertions config.warnings;
in
{
  options.system.topLevel = lib.mkOption {
    type = lib.types.path;
    description = "top-level system derivation";
    readOnly = true;
  };

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
        set' = lib.mapAttrs (a: {deps, text}:
          {
            inherit deps;
            text = ''
              #### Activation script snippet ${a}:
              ${lib.optionalString (deps != []) "wait${lib.concatMapStrings (d: " $PID_" + d) deps}"}
              (
              ${text}
              status=$?

              if (( status > 0 )); then
                echo "Activation script snippet '${a}' failed ($status)" >>$ERROR_FILE
              fi
              ) &

              PID_${a}=$!
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

          # Ensure a consistent umask.
          umask 0022

          ERROR_FILE=$(s6-uniquename /run/activation-errors)

          ${lib.textClosureMap lib.id set' (lib.attrNames set')}

          # Wait for all children to exit.
          wait

          # Make this configuration the current configuration.
          # The readlink is there to ensure that when $systemConfig = /system
          # (which is a symlink to the store), /run/current-system is still
          # used as a garbage collection root.
          ln -sfn "$(readlink -f "$systemConfig")" /run/current-system

          if [ -f "$ERROR_FILE" ]; then
            cat $ERROR_FILE
            rm $ERROR_FILE
            exit 1
          fi
        '';

    system.activation.scripts.specialfs = ''
      echo "specialfs stub here..."
      mkdir -p /bin /etc /run /tmp /usr /var/{cache,db,empty,lib,log,spool}
      [ ! -e /var/run ] && ln -s -n /run /var/run
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
      s6-portable-utils # s6-ln, s6-uniquename
    ];

    system.topLevel =  checkAssertWarn (pkgs.stdenvNoCC.mkDerivation {
      name = "finix-system";
      preferLocalBuild = true;
      allowSubstitutes = false;
      buildCommand =
        ''
          mkdir -p $out

          cp ${config.system.activation.out} $out/activate
          cp ${config.boot.init.script} $out/init

          ${pkgs.coreutils}/bin/ln -s ${config.environment.path} $out/sw

          substituteInPlace $out/activate --subst-var-by systemConfig $out
          substituteInPlace $out/init --subst-var-by systemConfig $out
        ''
        + lib.optionalString config.boot.kernel.enable ''
          ${pkgs.coreutils}/bin/ln -s ${config.boot.kernelPackages.kernel}/bzImage $out/kernel
          ${pkgs.coreutils}/bin/ln -s ${config.system.modulesTree} $out/kernel-modules
          ${pkgs.coreutils}/bin/ln -s ${config.hardware.firmware}/lib/firmware $out/firmware
        ''
        + lib.optionalString config.boot.initrd.enable ''
          ${pkgs.coreutils}/bin/ln -s ${config.boot.initrd.package}/initrd $out/initrd
        '';
    });

    boot.kernelParams = [ "init=${config.system.topLevel}/init" ];
  };
}
