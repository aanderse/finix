final: prev: {

  lib = import ../pkgs/lib |> prev.lib.extend;

  # TODO: upstream in nixpkgs
  finit = prev.callPackage ../pkgs/finit { };

  formats = import ../pkgs/pkgs-lib/formats { inherit (final) lib; pkgs = prev; };

  # see https://github.com/eudev-project/eudev/pull/290
  eudev = prev.eudev.overrideAttrs (o: {
    patches = (o.patches or [ ]) ++ [
      (final.fetchpatch {
        name = "s6-readiness.patch";
        url = "https://github.com/eudev-project/eudev/pull/290/commits/48e9923a1d0218d714989d8aec119e301aa930ae.patch";
        sha256 = "sha256-Icor2v2OYizquLW0ytYONjhCUW+oTs5srABamQR9Uvk=";
      })
    ];
  });

  syndicate-server = final.callPackage ../pkgs/syndicate-server { };

  syndicate_utils = final.callPackage ../pkgs/syndicate_utils { };

  synit-pid1 = final.callPackage ../pkgs/synit-pid1 { };

  synit-service = final.callPackage ../pkgs/synit-service { };

  tclPackages = import ../pkgs/tcl-modules |> prev.tclPackages.overrideScope;

  # modern fork of sysklogd - same author as finit
  sysklogd = prev.callPackage ../pkgs/sysklogd { };

  # relevant software for systems without logind - potentially useful to finix
  pam_xdg = prev.callPackage ../pkgs/pam_xdg { };
}
