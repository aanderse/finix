{ lib, config, pkgs, ... }:

let
  inherit (lib)
    mkIf
    getExe'
    ;
in
{
  config = mkIf config.synit.enable {

    # Collect information on network devices when triggered
    # by uevent and assert it into the machine dataspace.
    services.mdevd.hotplugRules = let
        netScript = pkgs.execline.passthru.writeScript "mdevd-net.el" [] ''
          importas -S ACTION
          importas -S INTERFACE
          define ASSERTION /run/synit/config/machine/interface-''${INTERFACE}.pr
          case $ACTION {
            remove { rm -f $ASSERTION }
          }
          pipeline -w {
            redirfd -w 1 $ASSERTION
            ${pkgs.jq}/bin/jq --raw-output "\"<interface ''${INTERFACE} \\(.[0])>\""
          }
          ${pkgs.iproute2}/bin/ip --json link show $INTERFACE
        '';
      in "-SUBSYSTEM=net;DEVPATH=.*/net/*;.* 0:0 600 &${netScript}";

    # A Tcl script responds to assertions in the 
    # network dataspace by executing iproute2 commands
    # and relaying actually existing configuration into
    # the machine dataspaces.
    # See ./static/core/network-config.pr for the routing
    # of assertions.
    synit.daemons.network-configurator =
      let inherit (pkgs.tclPackages) tcl sycl; in {
        argv = [ (getExe' tcl "tclsh") ./networking.tcl ];
        env.TCLLIBPATH = "${sycl}/lib/${sycl.name}";
        path = [ pkgs.iproute2 ];
        protocol = "text/syndicate";
        provides = [ [ "milestone" "network" ] ];
        logging.enable = false; # Errors only.
        # TODO: disable readyOnStart.
      };
    synit.profile.config = [ (builtins.readFile ./networking.pr) ];
  };
}
