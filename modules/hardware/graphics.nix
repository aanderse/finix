{ config, pkgs, lib, ... }:
let
  cfg = config.hardware.graphics;

  driversEnv = pkgs.buildEnv {
    name = "graphics-drivers";
    paths = [ cfg.package ] ++ cfg.extraPackages;
  };

  driversEnv32 = pkgs.buildEnv {
    name = "graphics-drivers-32bit";
    paths = [ cfg.package32 ] ++ cfg.extraPackages32;
  };

  gidOf = name: toString config.ids.gids.${name};
in
{
  options.hardware.graphics = {
    enable = lib.mkOption {
      description = ''
        Whether to enable hardware accelerated graphics drivers.

        This is required to allow most graphical applications and
        environments to use hardware rendering, video encode/decode
        acceleration, etc.

        This option should be enabled by default by the corresponding modules,
        so you do not usually have to set it yourself.
      '';
      type = lib.types.bool;
      default = false;
    };

    enable32Bit = lib.mkOption {
      description = ''
        On 64-bit systems, whether to also install 32-bit drivers for
        32-bit applications (such as Wine).
      '';
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      description = ''
        The package that provides the default driver set.
      '';
      type = lib.types.package;
      internal = true;
    };

    package32 = lib.mkOption {
      description = ''
        The package that provides the 32-bit driver set. Used when {option}`enable32Bit` is enabled.
        set.
      '';
      type = lib.types.package;
      internal = true;
    };

    extraPackages = lib.mkOption {
      description = ''
        Additional packages to add to the default graphics driver lookup path.
        This can be used to add OpenCL drivers, VA-API/VDPAU drivers, etc.

        ::: {.note}
        intel-media-driver supports hardware Broadwell (2014) or newer. Older hardware should use the mostly unmaintained intel-vaapi-driver driver.
        :::
      '';
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "with pkgs; [ intel-media-driver intel-ocl intel-vaapi-driver ]";
    };

    extraPackages32 = lib.mkOption {
      description = ''
        Additional packages to add to 32-bit graphics driver lookup path on 64-bit systems.
        Used when {option}`enable32Bit` is set. This can be used to add OpenCL drivers, VA-API/VDPAU drivers, etc.

        ::: {.note}
        intel-media-driver supports hardware Broadwell (2014) or newer. Older hardware should use the mostly unmaintained intel-vaapi-driver driver.
        :::
      '';
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "with pkgs.pkgsi686Linux; [ intel-media-driver intel-vaapi-driver ]";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable32Bit -> pkgs.stdenv.hostPlatform.isx86_64;
        message = "`hardware.graphics.enable32Bit` only makes sense on a 64-bit system.";
      }
      {
        assertion = cfg.enable32Bit -> (config.boot.kernelPackages.kernel.features.ia32Emulation or false);
        message = "`hardware.graphics.enable32Bit` requires a kernel that supports 32-bit emulation";
      }
    ];

    services.mdevd.hotplugRules = "dri/* 0:${gidOf "video"} 660";

    services.tmpfiles.graphics.rules = [
      "L+ /run/opengl-driver - - - - ${driversEnv}"
    ] ++ lib.optionals cfg.enable32Bit [
      "L+ /run/opengl-driver-32 - - - - ${driversEnv32}"
    ];

    synit.daemons.opengl-driver = {
      argv = lib.optionals cfg.enable32Bit [
        "foreground" "s6-ln" "-sf" driversEnv32 "/run/opengl-driver-32" ""
      ] ++ [
        "s6-ln" "-sf" driversEnv "/run/opengl-driver"
      ];
      restart = "on-error";
      logging.enable = lib.mkDefault false;
      provides = [ [ "milestone" "graphics" ] ];
    };

    hardware.graphics.package = lib.mkDefault pkgs.mesa;
    hardware.graphics.package32 = lib.mkDefault pkgs.pkgsi686Linux.mesa;
  };
}
