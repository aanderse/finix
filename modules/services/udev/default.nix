{ config, pkgs, lib, ... }:
let
  cfg = config.services.udev;

  # Udev has a 512-character limit for ENV{PATH}, so create a symlink
  # tree to work around this.
  udevPath = pkgs.buildEnv {
    name = "udev-path";
    paths = cfg.path;
    pathsToLink = [ "/bin" "/sbin" ];
    ignoreCollisions = true;
  };

  # Perform substitutions in all udev rules files.
  udevRulesFor = { name, udevPackages, udevPath, udev, binPackages }: pkgs.runCommand name
    { preferLocalBuild = true;
      allowSubstitutes = false;
      packages = lib.unique (map toString udevPackages);
    }
    ''
      mkdir -p $out
      shopt -s nullglob
      set +o pipefail

      # Set a reasonable $PATH for programs called by udev rules.
      echo 'ENV{PATH}="${udevPath}/bin:${udevPath}/sbin"' > $out/00-path.rules

      # Add the udev rules from other packages.
      for i in $packages; do
        echo "Adding rules for package $i"
        for j in $i/{etc,lib,var/lib}/udev/rules.d/*; do
          echo "Copying $j to $out/$(basename $j)"
          cat $j > $out/$(basename $j)
        done
      done

      # Fix some paths in the standard udev rules.  Hacky.
      for i in $out/*.rules; do
        substituteInPlace $i \
          --replace-quiet \"/sbin/modprobe \"${pkgs.kmod}/bin/modprobe \
          --replace-quiet \"/sbin/mdadm \"${pkgs.mdadm}/sbin/mdadm \
          --replace-quiet \"/sbin/blkid \"${pkgs.util-linux}/sbin/blkid \
          --replace-quiet \"/bin/mount \"${pkgs.util-linux}/bin/mount \
          --replace-quiet /usr/bin/readlink ${pkgs.coreutils}/bin/readlink \
          --replace-quiet /usr/bin/cat ${pkgs.coreutils}/bin/cat \
          --replace-quiet /usr/bin/basename ${pkgs.coreutils}/bin/basename 2>/dev/null
      done

      echo -n "Checking that all programs called by relative paths in udev rules exist in ${udev}/lib/udev... "
      import_progs=$(grep 'IMPORT{program}="[^/$]' $out/* |
        sed -e 's/.*IMPORT{program}="\([^ "]*\)[ "].*/\1/' | uniq)
      run_progs=$(grep -v '^[[:space:]]*#' $out/* | grep 'RUN+="[^/$]' |
        sed -e 's/.*RUN+="\([^ "]*\)[ "].*/\1/' | uniq)
      for i in $import_progs $run_progs; do
        if [[ ! -x ${udev}/lib/udev/$i && ! $i =~ socket:.* ]]; then
          echo "FAIL"
          echo "$i is called in udev rules but not installed by udev"
          exit 1
        fi
      done
      echo "OK"

      echo -n "Checking that all programs called by absolute paths in udev rules exist... "
      import_progs=$(grep 'IMPORT{program}="/' $out/* |
        sed -e 's/.*IMPORT{program}="\([^ "]*\)[ "].*/\1/' | uniq)
      run_progs=$(grep -v '^[[:space:]]*#' $out/* | grep 'RUN+="/' |
        sed -e 's/.*RUN+="\([^ "]*\)[ "].*/\1/' | uniq)
      for i in $import_progs $run_progs; do
        if [[ ! -x $i ]]; then
          echo "FAIL"
          echo "$i is called in udev rules but is not executable or does not exist"
          exit 1
        fi
      done
      echo "OK"

      filesToFixup="$(for i in "$out"/*; do
        # list all files referring to (/usr)/bin paths, but allow references to /bin/sh.
        grep -P -l '\B(?!\/bin\/sh\b)(\/usr)?\/bin(?:\/.*)?' "$i" || :
      done)"

      if [ -n "$filesToFixup" ]; then
        echo "Consider fixing the following udev rules:"
        echo "$filesToFixup" | while read localFile; do
          remoteFile="origin unknown"
          for i in ${toString binPackages}; do
            for j in "$i"/*/udev/rules.d/*; do
              [ -e "$out/$(basename "$j")" ] || continue
              [ "$(basename "$j")" = "$(basename "$localFile")" ] || continue
              remoteFile="originally from $j"
              break 2
            done
          done
          refs="$(
            grep -o '\B\(/usr\)\?/s\?bin/[^ "]\+' "$localFile" \
              | sed -e ':r;N;''${s/\n/ and /;br};s/\n/, /g;br'
          )"
          echo "$localFile ($remoteFile) contains references to $refs."
        done
        exit 1
      fi
    '';

  hwdbBin = pkgs.runCommand "hwdb.bin"
    { preferLocalBuild = true;
      allowSubstitutes = false;
      packages = lib.unique (map toString ([ pkgs.udev ] ++ cfg.packages));
    }
    ''
      mkdir -p etc/udev/hwdb.d
      for i in $packages; do
        echo "Adding hwdb files for package $i"
        for j in $i/{etc,lib,var/lib}/udev/hwdb.d/*; do
          ln -s $j etc/udev/hwdb.d/$(basename $j)
        done
      done

      echo "Generating hwdb database..."
      # hwdb --update doesn't return error code even on errors!
      res="$(${pkgs.buildPackages.systemd}/bin/systemd-hwdb --root=$(pwd) update 2>&1)"
      echo "$res"
      [ -z "$(echo "$res" | egrep '^Error')" ]
      mv etc/udev/hwdb.bin $out
    '';
in
{
  options.services.udev = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.eudev;
    };

    packages = lib.mkOption {
      type = with lib.types; listOf path;
      default = [];
      description = ''
        List of packages containing {command}`udev` rules.
        All files found in
        {file}`«pkg»/etc/udev/rules.d` and
        {file}`«pkg»/lib/udev/rules.d`
        will be included.
      '';
      apply = map lib.getBin;
    };

    path = lib.mkOption {
      type = with lib.types; listOf path;
      default = [];
      description = ''
        Packages added to the {env}`PATH` environment variable when
        executing programs from Udev rules.

        coreutils, gnu{sed,grep}, util-linux
        automatically included.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # services.udev.packages = [ extraUdevRules extraHwdbFile ];
    services.udev.path = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.util-linux cfg.package ];

    # adapted from https://github.com/troglobit/finit/blob/master/system/10-hotplug.conf.in
    environment.etc."finit.d/udev.conf".text = ''
      service cgroup.system <!> name:udevd notify:s6 pid:udevd log [S12345789] ${cfg.package}/bin/udevd --ready-notify=%n ${lib.optionalString cfg.debug " -D"} -- device event daemon (${cfg.package.pname})

      # Wait for udevd to start, then trigger coldplug events and module loading.
      # The last 'settle' call waits for it to finalize processing all uevents.
      run nowarn cgroup.init :1 [S] <service/udevd/ready> log ${cfg.package}/bin/udevadm settle -t 0                  --
      run nowarn cgroup.init :2 [S] <service/udevd/ready> log ${cfg.package}/bin/udevadm control --reload             --
      run nowarn cgroup.init :3 [S] <service/udevd/ready> log ${cfg.package}/bin/udevadm trigger -c add -t devices    -- requesting device events
      run nowarn cgroup.init :4 [S] <service/udevd/ready> log ${cfg.package}/bin/udevadm trigger -c add -t subsystems -- requesting subsystem events
      run nowarn cgroup.init :5 [S] <service/udevd/ready> log ${cfg.package}/bin/udevadm settle -t 30                 -- waiting for udev to finish
    '';

    environment.etc."udev/hwdb.bin".source = hwdbBin;
    environment.etc."udev/rules.d".source = udevRulesFor {
      name = "udev-rules";
      udevPackages = cfg.packages;
      binPackages = cfg.packages;
      udev = cfg.package;

      inherit udevPath;
    };

    # where does this belong?
    system.activation.scripts.udevd = lib.mkIf config.boot.kernel.enable {
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
  };
}
