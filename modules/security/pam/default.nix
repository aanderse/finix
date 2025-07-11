{ config, pkgs, lib, ... }:
let
  pamOpts = { name, ... }: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = name;
      };

      text = lib.mkOption {
        type = lib.types.lines;
      };
    };
  };
in
{
  options.security.pam = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    services = lib.mkOption {
      type = with lib.types; attrsOf (submodule pamOpts);
      default = { };
    };
  };

  config = {
    environment.etc =
      let
        etcTree = lib.mapAttrs' (k: v: lib.nameValuePair "pam.d/${k}" {
          inherit (v) text;
        }) (lib.filterAttrs (_: v: v.enable) config.security.pam.services);

        debug = lib.mkIf config.security.pam.debug {
          "pam_debug".text = "";
        };

        env = {
          "security/pam_env.conf".text = ''
            PATH                        DEFAULT="${config.security.wrapperDir}:/run/current-system/sw/bin"
            NIX_REMOTE                  DEFAULT="daemon"
            EDITOR                      DEFAULT="micro"

            NIX_XDG_DESKTOP_PORTAL_DIR  DEFAULT="/run/current-system/sw/share/xdg-desktop-portal/portals"
            XCURSOR_PATH                DEFAULT="/run/current-system/sw/share/icons:/run/current-system/sw/share/pixmaps"
            XDG_DATA_DIRS               DEFAULT="/run/current-system/sw/share"
            XDG_CONFIG_DIRS             DEFAULT="/etc/xdg:/run/current-system/sw/etc/xdg"
          '';
        };
      in
        lib.mkMerge [ debug env etcTree ];

    security.pam.services.other = {
      text = ''
        auth     required pam_warn.so
        auth     required pam_deny.so
        account  required pam_warn.so
        account  required pam_deny.so
        password required pam_warn.so
        password required pam_deny.so
        session  required pam_warn.so
        session  required pam_deny.so
      '';
    };

    security.wrappers = {
      unix_chkpwd = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${pkgs.pam}/bin/unix_chkpwd";
      };
    };
  };
}
