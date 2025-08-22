{ config, pkgs, lib, ... }:
let
  cfg = config.boot.init;

  # Sort and join the command-line of PID 1.
  pid1Argv =
    (lib.textClosureList cfg.pid1.argv (builtins.attrNames cfg.pid1.argv))
    |> lib.concatLists
    |> lib.concatMapStringsSep "\n" lib.escapeExeclineArg;
in
{
  # TODO: something not quite sitting right with me here
  options.boot.init = {
    script = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
    };

    pid1 = {
      argv = lib.mkOption {
        description = ''
          The PID 1 command line as a closure-list.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              deps = lib.mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                description = "List of argument groups that must preceded this one.";
              };
              text = lib.mkOption {
                type = with lib.types; uniq (either str (listOf (either str path)));
                description = "Group of arguments for the pid1 command-line.";
              };
            };
          }
        );
      };
      env = lib.mkOption {
        description = ''
          Environment variables to start PID 1 with.
        '';
        type = with lib.types; attrsOf str;
        default = { };
      };
    };
  };

  config = {

    boot.init.pid1.argv = {
      # Set the environment via argv.
      env.text = cfg.pid1.env
        |> builtins.attrNames
        |> lib.concatMap (key: [ "export" key cfg.pid1.env.${key} ]);

      # How "@systemConfig@/activate" is called is declared elsewhere.
      activation.deps = [ "env" ];
    };

    boot.init.script = pkgs.execline.passthru.writeScript "init" "-P" ''
      background {
        ${pkgs.s6-portable-utils}/bin/s6-echo "\n[1;32m<<< finix - stage 2 >>>[0m\n"
      }

      # Record the boot configuration.
      # Create /run/current-system so that activation
      # always happens with a valid symlink there.
      background {
        forx -E -p DIR { /run/booted-system /run/current-system }
        ${pkgs.s6-portable-utils}/bin/s6-ln -s -f -n "@systemConfig@" $DIR
      }

      wait { }
      ${pid1Argv}
    '';
  };
}
