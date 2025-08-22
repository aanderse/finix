{ lib, config, pkgs, ... }:

let
  inherit (lib)
    attrValues
    getExe
    getExe'
    makeBinPath
    mkDefault
    mkEnableOption
    mkPackageOption
    mkIf
    mkOption
    optionals
    quoteExecline
    ;

  writeExeclineScript = pkgs.execline.passthru.writeScript;

  cfg = config.synit;

  synitPackages = attrValues {
    inherit (pkgs) execline s6 s6-linux-utils s6-portable-utils;
    inherit (cfg.syndicate-server) package;
  };

in
{
  imports = [
    ./daemons.nix
    ./dependencies.nix
    ./filesystems.nix
    ./logging.nix
    ./networking.nix
    ./profile.nix
  ];

  options.synit = {
    enable = mkOption {
      default = config.boot.serviceManager == "synit";
      defaultText = ''config.boot.serviceManager == "synit"'';
      readOnly = true;
    };

    logging = {
      logToFileSystem = mkEnableOption "logging to the file-system by default" // {
        default = true;
      };
    };

    syndicate-server.package = mkPackageOption pkgs "syndicate-server" { };

    pid1.package = mkPackageOption pkgs "synit-pid1" { };

  };

  config = mkIf cfg.enable {

    boot.init.pid1 = {
      env = {
        # This tells Rust programs built with jemallocator to be very aggressive about keeping their
        # heaps small. Synit currently targets small machines. Without this, I have seen the system
        # syndicate-server take around 300MB of heap when doing not particularly much; with this, it
        # takes about 15MB in the same state. There is a performance penalty on being so aggressive
        # about heap size, but it's more important to stay small in this circumstance right now. - tonyg
        "_RJEM_MALLOC_CONF" = "narenas:1,tcache:false,dirty_decay_ms:0,muzzy_decay_ms:0";
        PATH = makeBinPath synitPackages;
      };
      argv = {

        activation = {
          text = quoteExecline [
            "foreground" [
              "@systemConfig@/activate"
            ]
          ];
        };

        pid1 = {
          deps = [ "activation" ];
          text = [
            (getExe cfg.pid1.package)
          ];
        };

        logger = {
          deps = [  "pid1" ];
          text = mkDefault (optionals cfg.logging.logToFileSystem (quoteExecline [
            "foreground" [ "s6-mkdir" "-p" "/var/log/synit" ]
            "fdswap" "1" "2"
            "pipeline" "-w" [ "s6-log" "/var/log/synit" ]
            "fdswap" "1" "2"
          ]));
        };

        syndicate-server = {
          deps = [ "activation" "logger" ];
          text = mkDefault [
            "syndicate-server"
            "--inferior"
          ];
        };
        syndicate-server-config = {
          deps = [ "syndicate-server" ];
          text = mkDefault [
            "--config" "${./boot.pr}"
          ];
        };
      };
    };

    environment.systemPackages = synitPackages ++ [
      pkgs.synit-service
    ];

    # Only tested with mdevd.
    services.mdevd.enable = mkDefault true;

    system.activation.scripts.synitConfig = {
      deps = [ "specialfs" ];
      text = ''
        for D in /etc/syndicate/core /run/synit/config/{core,machine,network,profile,state}; do
          s6-mkdir -m 750 -p $D
          s6-chown -g 1 $D
        done
      '';
    };

  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
