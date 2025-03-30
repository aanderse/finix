{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  autoreconfHook,
  pkg-config,
  libite,
  libuev,
  util-linux,
  procps,
}:

stdenv.mkDerivation rec {
  pname = "finit";
  version = "4.11+";

  src = fetchFromGitHub {
    owner = "troglobit";
    repo = "finit";
    rev = "1f47718012f6239bcea774b7ca11cce032c432a4";
    hash = "sha256-fZUaY+nc/zKlIpOV5Zcwh7HEO8rHEKh+u8nihhrRFa8=";
  };

  postPatch = ''
    substituteInPlace plugins/modprobe.c --replace-fail \
      '"/lib/modules"' '"/run/booted-system/kernel-modules/lib/modules"'
  '';

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    installShellFiles
  ];

  buildInputs = [
    libite
    libuev
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--localstatedir=/var"

    # tweak default plugin list
    "--enable-modprobe-plugin=yes"
    "--enable-modules-load-plugin=yes"
    "--enable-hotplug-plugin=no"
    "--enable-urandom-plugin=no" # FIXME: causing segfault, haven't looked into why
  ];

  env.NIX_CFLAGS_COMPILE = toString [
    "-D_PATH_LOGIN=\"${util-linux}/bin/login\""
    "-DSYSCTL_PATH=\"${procps}/bin/sysctl\""
  ];

  postInstall = ''
    installShellCompletion --cmd initctl \
      --bash initctl
  '';

  meta = {
    description = "Fast init for Linux";
    mainProgram = "initctl";
    homepage = "https://troglobit.com/projects/finit/";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ aanderse ];
    platforms = lib.platforms.unix;
  };
}
