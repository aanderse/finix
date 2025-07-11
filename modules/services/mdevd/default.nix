{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    getExe
    getExe'
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;

  writeExeclineScript = pkgs.execline.passthru.writeScript;
  gidOf = name: toString config.ids.gids.${name};

  cfg = config.services.mdevd;

  # Rules for the special standalone devices to be created at boot.
  specialRules = let audio = gidOf "audio"; tty = gidOf "tty"; in ''
    null      0:0 666 +importas -S MDEV s6-chmod 666 /dev/$MDEV
    zero      0:0 666 +importas -S MDEV s6-chmod 666 /dev/$MDEV
    full      0:0 666 +importas -S MDEV s6-chmod 666 /dev/$MDEV
    random    0:0 444 +importas -S MDEV s6-chmod 444 /dev/$MDEV
    urandom   0:0 444 +importas -S MDEV s6-chmod 444 /dev/$MDEV
    hwrandom  0:0 444 +importas -S MDEV s6-chmod 444 /dev/$MDEV

    ptmx        0:${tty} 666
    pty.*       0:${tty} 660
    tty         0:${tty} 666
    tty[0-9]*   0:${tty} 660

    vcsa*[0-9]* 0:${tty} 660
    ttyS[0-9]*  0:${gidOf "uucp"} 660

    snd/*       0:${audio} 660
  '';

  # Insert modules for devices.
  modaliasRule = "-$MODALIAS=.* 0:0 660 +importas m MODALIAS modprobe --quiet $m";

  # We need symlinks in /dev/disk/{by-id,by-label,by-uuid}
  # so we run this script for block device events.
  # Requires blkid from util-linux be on $PATH.
  devDiskScript = writeExeclineScript "mdevd-disk.el" "" ''
    importas -S ACTION
    importas -S MDEV
    case $ACTION
    {
      add {
        # Udev compatibility hack.
        foreground { s6-mkdir -p /dev/disk/by-id }
        foreground { s6-ln -s ../../$MDEV /dev/disk/by-id/$MDEV }

        forbacktickx -pE LINE { blkid --output export /dev/$MDEV }
        case -N $LINE {
          ^LABEL=(.*) {
            foreground { s6-mkdir -p /dev/disk/by-label }
            importas -S 1
            s6-ln -s ../../$MDEV /dev/disk/by-label/$1
          }
          ^UUID=(.*) {
            foreground { s6-mkdir -p /dev/disk/by-uuid }
            importas -S 1
            s6-ln -s ../../$MDEV /dev/disk/by-uuid/$1
          }
        }
      }
      remove {
        foreground { s6-rmrf /dev/disk/by-id/$MDEV }
        forbacktickx -pE LINE { blkid --output export /dev/$MDEV }
        case -N $LINE {
          ^LABEL=(.*) { importas -S 1 s6-rmrf /dev/disk/by-label/$1 }
           ^UUID=(.*) { importas -S 1 s6-rmrf /dev/disk/by-uuid/$1  }
        }
      }
    }
  '';

  devDiskRule = "-SUBSYSTEM=block;.* 0:${gidOf "disk"} 660 &${devDiskScript}";
in
{
  options.services.mdevd = {
    enable = mkEnableOption "the mdevd device hotplug manager";

    package = mkPackageOption pkgs [ "mdevd" ] { };

    hotplugRules = mkOption {
      type = types.lines;
      description = ''
        Mdevd rules for hotplug events.
        These rules are active after the initial `mdevd` daemon
        has coldbooted with the `services.mdevd.coldplug` rules.
      '';
    };

    coldplugRules = mkOption {
      type = types.lines;
      description = ''
        Mdeved rules for coldplug events during the initramfs stage of booting.
      '';
    };
  };

  config = mkIf cfg.enable {

    # Populate with boot rules.
    services.mdevd = {
      hotplugRules = lib.concatLines [
        modaliasRule
        specialRules
        devDiskRule
      ];
      coldplugRules = lib.concatLines [
        modaliasRule
        specialRules
        devDiskRule
      ];
    };

    # Mdevd coldplugs the system during the stage-1 init in initramfs.
    # See ../../boot/initrd/default.nix
    boot.initrd.contents = [
        { target = "/etc/mdev.conf";
          source = pkgs.writeText "mdev.conf" config.services.mdevd.coldplugRules;
        }
        { source = devDiskScript;
          target = "/etc/dev-disk.el";
        }
    ];

    environment.etc."mdev.conf".text = config.services.mdevd.hotplugRules;

    finit.services.mdevd = {
      description = "device event daemon (mdevd)";
      command = "${getExe cfg.package} -O 4 -D %n -f /etc/mdev.conf";
      runlevels = "S12345789";
      cgroup.name = "init";
      notify = "s6";
    };

    finit.run.coldplug = {
      description = "cold plugging system";
      command = getExe' cfg.package "mdevd-coldplug";
      runlevels = "S";
      conditions = "service/mdevd/ready";
      cgroup.name = "init";
    };

    # TODO: share between udev and mdevd
    system.activation.scripts.mdevd = lib.mkIf config.boot.kernel.enable {
      text = ''
        # The deprecated hotplug uevent helper is not used anymore
        if [ -e /proc/sys/kernel/hotplug ]; then
          echo "" > /proc/sys/kernel/hotplug
        fi

        # Allow the kernel to find our firmware.
        if [ -e /sys/module/firmware_class/parameters/path ]; then
          echo -n "${config.hardware.firmware}/lib/firmware" > /sys/module/firmware_class/parameters/path
        fi
      '';
    };

    # Start a hotpluging mdevd after the stage-2 init.
    synit.core.daemons.mdevd = {
      argv = [
        "${cfg.package}/bin/mdevd"
        "-D" "3"
        "-O" "2"
	# TODO: reload on SIGHUP.
        "-f" "/etc/mdev.conf"
      ];
      readyOnNotify = 3;
      path = with pkgs; [ kmod util-linux ];
      # Upstream claims mdevd is terse enough to run
      # without a dedicated logging destination.
      logging.enable = false;
    };

    # Hold core back until another coldplug completes.
    synit.core.daemons.mdevd-coldplug = {
      argv = [ (getExe' cfg.package "mdevd-coldplug") "-O" "2" ];
      restart = "on-error";
      requires = [ { key = [ "daemon" "mdevd" ]; } ];
      logging.enable = false;
    };
  };
}
