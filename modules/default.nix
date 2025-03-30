let
  serviceModules = builtins.mapAttrs (dir: _:
    ./services/${dir}
  ) (builtins.removeAttrs (builtins.readDir ./services) [ "README.md" ]);
in
{
  default = {
    imports = [
      ./boot
      ./environment
      ./filesystems
      ./finit
      ./fonts
      ./hardware
      ./i18n
      ./misc
      ./networking
      # ./nixpkgs
      ./security
      ./system/activation
      ./time
      ./users
      ./xdg
    ];
  };
} // serviceModules
