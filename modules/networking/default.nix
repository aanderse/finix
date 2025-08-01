{ config, pkgs, lib, ... }:
let
  cfg = config.networking;

  deviceOpt = lib.mkOption {
    type = lib.types.str;
    description = "Network attachment device.";
    example = "eth0";
  };

  prefixLengthOpt = lib.mkOption {
    type = lib.types.int;
    description = "Network prefix length.";
  };

  addressesSubmodule = addrLen: {
    options = {
      device = deviceOpt;

      local = lib.mkOption {
        type = lib.types.str;
        description = "Local address.";
      };

      prefixLength = prefixLengthOpt // {
        default = addrLen;
      };
    };
  };

  routeSubmodule = lib.types.submodule {
    options = {
      device = deviceOpt;

      gateway = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "Network gateway to use as a default route.";
      };

      prefix = lib.mkOption {
        type = with lib.types; nullOr str;
        description = "Route addressing prefix.";
        default = null;
      };
      prefixLength = prefixLengthOpt // {
        type = lib.types.nullOr prefixLengthOpt.type;
        default = null;
      };
    };
  };

  mkListOfSubmodule = attrs:
    lib.mkOption {
      type = with lib.types; listOf (submodule attrs);
      default = [ ];
    };

in
{
  options.networking = {
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "finix";
    };

    hosts = lib.mkOption {
      type = with lib.types; attrsOf (listOf str);
      example = lib.literalExpression ''
        {
          "127.0.0.1" = [ "foo.bar.baz" ];
          "192.168.0.2" = [ "fileserver.local" "nameserver.local" ];
        };
      '';
      description = ''
        Locally defined maps of hostnames to IP addresses.
      '';
    };

    ipv4 = {
      addresses = mkListOfSubmodule (addressesSubmodule 32 // {
        example = [
          { device = "eth0"; local = "192.0.2.7"; prefixLength = 24; }
          { device = "eth1"; local = "203.0.113.175"; prefixLength = 32; }
        ];
      });
      routes = mkListOfSubmodule (routeSubmodule // {
        example = [
          { device = "eth0"; prefix = "192.0.2.0"; prefixLengh = 24; }
          { device = "eth0"; gateway = "192.0.2.1"; }
        ];
      });
    };

    ipv6 = {
      addresses = mkListOfSubmodule (addressesSubmodule 128 // {
        example = [
          { device = "eth0"; local = "2001:db8:1::3"; prefixLength = 64; }
          { device = "eth1"; local = "fd12:3456::7"; prefixLength = 48; }
        ];
      });
      routes = mkListOfSubmodule (routeSubmodule // {
        example = [
          { device = "eth0"; prefix = "2001:db8:1::"; prefixLengh = 64; }
          { device = "eth0"; gateway = "2001:db8:1::1"; }
        ];
      });
    };

  };

  config = {
    boot.kernel.sysctl = {
      # allow all users to do ICMP echo requests (ping)
      "net.ipv4.ping_group_range" = lib.mkDefault "0 2147483647";

      # Generate link-local addresses.
      "net.ipv6.conf.all.addr_gen_mode" = lib.mkDefault 3;
    };

    networking.hosts = {
      localhost = [ "127.0.0.1" ];
      ${config.networking.hostName} = [ "127.0.0.2" ];
    };

    environment.etc = {
      hostname.text = cfg.hostName + "\n";

      hosts.text =
        let
          oneToString = set: ip: ip + " " + lib.concatStringsSep " " set.${ip} + "\n";
          allToString = set: lib.concatMapStrings (oneToString set) (lib.attrNames set);
        in
          allToString (lib.filterAttrs (_: v: v != [ ]) cfg.hosts)
      ;

      # /etc/services: TCP/UDP port assignments.
      services.source = pkgs.iana-etc + "/etc/services";

      # /etc/protocols: IP protocol numbers.
      protocols.source  = pkgs.iana-etc + "/etc/protocols";

      # /etc/netgroup: Network-wide groups.
      netgroup.text = lib.mkDefault "";

      # /etc/host.conf: resolver configuration file
      "host.conf".text = ''
        multi on
      '';

    } // lib.optionalAttrs (pkgs.stdenv.hostPlatform.libc == "glibc") {
      # /etc/rpc: RPC program numbers.
      rpc.source = pkgs.stdenv.cc.libc.out + "/etc/rpc";
    };
  };
}
