{ testenv ? import ./testenv { } }:

let
  inherit (testenv) pkgs;
in
testenv.mkTest {
  name = "ssh-synit";

  nodes.machine = { lib, ... }: {
    boot.serviceManager = "synit";
    services.dhcpcd.enable = true;
    services.openssh.enable = true;

    virtualisation.qemu.nics.eth0.args = [
      "hostfwd=tcp:127.0.0.1:2222-:22"
    ];
  };

  tclScript = ''
    machine spawn
    machine expect {synit_pid1: Awaiting signals...}
    machine expect {syndicate_server: inferior server instance}
    set timeout 20
    machine expect {*"machine"*+++*route eth0 ipv4*"10.0.2.0/24"*}
    machine expect {Server listening on 0.0.0.0 port 22.}
    ::spawn ${pkgs.openssh}/bin/ssh-keyscan -p 2222 127.0.0.1
    ::expect {[127.0.0.1]:2222 ssh-ed25519*\n}
    success
  '';
}
