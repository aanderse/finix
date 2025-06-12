{
  config,
  lib,
  ...
}:
{
  options = {
    boot.initrd.supportedFilesystems."9p" = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };

    boot.supportedFilesystems."9p" = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };

  config =
    let modsIf = v: lib.mkIf v [ "9p" ]; in
    {
      boot.kernelModules = modsIf config.boot.supportedFilesystems."9p".enable;
      boot.initrd.kernelModules = modsIf config.boot.initrd.supportedFilesystems."9p".enable;
    };
}
