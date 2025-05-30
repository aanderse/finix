final: prev: {
  # TODO: upstream in nixpkgs
  finit = prev.callPackage ../pkgs/finit { };

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

  # modern fork of sysklogd - same author as finit
  sysklogd = prev.callPackage ../pkgs/sysklogd { };

  # relevant software for systems without logind - potentially useful to finix
  pam_xdg = prev.callPackage ../pkgs/pam_xdg { };
}
