{ testenv ? import ./testenv { } }:

testenv.mkTest {
  name = "greetd-synit";

  nodes.machine = { lib, pkgs, ... }: {
    boot.serviceManager = "synit";

    security.pam.debug = true;

    services.greetd = {
      enable = true;
      settings.initial_session = {
        command = "${pkgs.bashInteractive}/bin/bash -l";
        user = "nobody";
      };
    };
  };

  tclScript = ''
    machine spawn
    machine expect {synit_pid1: Awaiting signals...}
    machine expect {syndicate_server: inferior server instance}
    machine expect {pam_unix(greetd:session): session opened for user nobody*\n}
    success
  '';
}
