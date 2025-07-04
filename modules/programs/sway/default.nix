{ config, pkgs, lib, ... }:
let
  cfg = config.programs.sway;
in
{
  options.programs.sway = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sway;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    environment.etc."wayland-sessions/sway.desktop".source = (pkgs.formats.ini { }).generate "sway.desktop" {
      "Desktop Entry" = {
        Name = "Sway";
        Comment = "An i3-compatible Wayland compositor";
        Exec = "${pkgs.dbus}/bin/dbus-run-session -- ${lib.getExe cfg.package}";
        Type = "Application";
      };
    };
  };
}
