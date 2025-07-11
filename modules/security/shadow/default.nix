{ config, pkgs, lib, ... }:
let
  cfg = config.security.shadow;
in
{
  imports = [ ./etc.nix ];

  options.security.shadow = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the `shadow` authentication suite, which provides critical programs such as `su`, `login`, `passwd`.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.shadow;
    };
  };

  config = lib.mkIf cfg.enable {
    security.pam.services.login = {
      text = ''
        # Account management.
        account required pam_unix.so # unix (order 10900)

        # Authentication management.
        auth optional pam_unix.so likeauth nullok # unix-early (order 11500)
        auth sufficient pam_unix.so likeauth nullok try_first_pass # unix (order 12800)
        auth required pam_deny.so # deny (order 13600)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=0 # env (order 10100)
        session required pam_unix.so # unix (order 10200)
        session required pam_loginuid.so # loginuid (order 10300)
        session required ${pkgs.linux-pam}/lib/security/pam_lastlog.so silent # lastlog (order 10700)

        ${lib.optionalString config.services.elogind.enable "session optional ${pkgs.elogind}/lib/security/pam_elogind.so"}
        ${lib.optionalString config.services.seatd.enable "session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so"}
      '';
    };

    security.pam.services.su = {
      text = ''
        # Account management.
        account required pam_unix.so # unix (order 10900)

        # Authentication management.
        auth sufficient pam_rootok.so # rootok (order 10200)
        auth required pam_faillock.so # faillock (order 10400)
        auth sufficient pam_unix.so likeauth try_first_pass # unix (order 11500)
        auth required pam_deny.so # deny (order 12300)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=0 # env (order 10100)
        session required pam_unix.so # unix (order 10200)
        session optional pam_xauth.so systemuser=99 xauthpath=${pkgs.xorg.xauth}/bin/xauth # xauth (order 12100)
      '';
    };

    security.pam.services.passwd = {
      text = ''
        # Account management.
        account required pam_unix.so # unix (order 10900)

        # Authentication management.
        auth sufficient pam_unix.so likeauth try_first_pass # unix (order 11500)
        auth required pam_deny.so # deny (order 12300)

        # Password management.
        password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

        # Session management.
        session required pam_env.so readenv=0 # env (order 10100)
        session required pam_unix.so # unix (order 10200)
      '';
    };

    security.wrappers =
      let
        mkSetuidRoot = source: {
          setuid = true;
          owner = "root";
          group = "root";
          inherit source;
        };
      in
        {
          su = mkSetuidRoot "${cfg.package.su}/bin/su";
          sg = mkSetuidRoot "${cfg.package.out}/bin/sg";
          newgrp = mkSetuidRoot "${cfg.package.out}/bin/newgrp";
          newuidmap = mkSetuidRoot "${cfg.package.out}/bin/newuidmap";
          newgidmap = mkSetuidRoot "${cfg.package.out}/bin/newgidmap";
        }
        // lib.optionalAttrs true /* config.users.mutableUsers */ {
          # chsh = mkSetuidRoot "${cfg.package.out}/bin/chsh";
          passwd = mkSetuidRoot "${cfg.package.out}/bin/passwd";
        };
  };
}
