{ lib, config, pkgs, ... }:

let
  cfg = config.synit.profile;

  inherit (lib)
    mkIf
    mkOption
    types
    ;

  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };

  profileHash = with builtins; cfg.file
    |> toString |> baseNameOf |> substring 0 12;

in
{
  options = {
    synit.profile = {
      name = mkOption {
        description = ''
          A unique identifier for the Synit
          system configuration profile result.
        '';
        readOnly = true;
      };
      config = mkOption {
        description = ''
          The syndicate-server configuration that
          comprises a system configuration profile.
        '';
        # TODO: List of Preserves type.
        type = with lib.types; listOf anything;
      };
      file = mkOption {
        description = ''
          The file that defines the Synit profile.
        '';
        readOnly = true;
      };
    };
  };

  config = mkIf config.synit.enable {

    synit.profile = {
      name = "${config.networking.hostName}-${profileHash}";
      file =
        let drv = preserves.generate "profile.pr" cfg.config;
        in drv.overrideAttrs ({ ... }: {
          postBuild = ''
            # Assert that this profile has been loaded.
            hash=$(basename $out)
            echo "<synit-profile \"${config.networking.hostName}-''${hash:0:12}\" loaded>" >> $out
          '';
        });
    };

    system.activation.scripts.synit-profile = {
      deps = [ "synit-config" ];
      text = ''
        mkdir -p /run/synit/config/profile/

        # Load the profile.
        echo '<synit-profile "${cfg.name}" load "${cfg.file}">' > /run/synit/config/profile/load-${profileHash}.pr

        # Activate the profile.
        echo '<synit-profile "${cfg.name}" activate>' >/run/synit/config/profile/activate-profile.pr
      '';
    };
  };
}
