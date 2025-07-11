{ pkgs, lib, ... }:
{
  imports = [
    ./providers.privileges.nix
  ];

  config = {
    security.pam.services.sudo.text = ''
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

    environment.etc.sudoers = {
      mode = "0440";
      text = lib.mkMerge [
        (lib.mkBefore ''
          # Don't edit this file. Set the NixOS options ‘security.sudo.configFile’
          # or ‘security.sudo.extraRules’ instead.
        '')

        (lib.mkAfter ''
          # extraConfig
          Defaults:root,%wheel timestamp_timeout=60

          # Keep terminfo database for root and %wheel.
          Defaults:root,%wheel env_keep+=TERMINFO_DIRS
          Defaults:root,%wheel env_keep+=TERMINFO
        '')

        ''
          root    ALL=(ALL:ALL)    SETENV: ALL
          %wheel  ALL=(ALL:ALL)    SETENV: ALL
        ''
      ];
    };

    security.wrappers = let
      owner = "root";
      group = "root";
      setuid = true;
      permissions = "u+rx,g+x,o+x";
    in {
      sudo = {
        source = "${pkgs.sudo.out}/bin/sudo";
        inherit owner group setuid permissions;
      };
      sudoedit = { # TODO: really? but the file is immutable...
        source = "${pkgs.sudo.out}/bin/sudoedit";
        inherit owner group setuid permissions;
      };
    };

    # this module supplies an implementation for `providers.privileges`
    providers.privileges.backend = lib.mkDefault "sudo";
  };
}
